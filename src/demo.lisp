(in-package #:ag-ui-backend-tui/demo)

;;; Glue: ai-agent → /ag-ui encoder → transcript / tuition.
;;; Core TUI stays AG-UI-only. This system is the product demo.

(defun %ht (&rest kvs)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kvs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun %add-params ()
  (%ht "type" "object"
       "properties" (%ht "a" (%ht "type" "number")
                         "b" (%ht "type" "number"))
       "required" (vector "a" "b")))

(defun %two-numbers (text)
  (let ((nums '()))
    (loop with i = 0
          with n = (length text)
          while (< i n)
          do (let ((c (char text i)))
               (if (or (digit-char-p c) (char= c #\-))
                   (multiple-value-bind (v pos)
                       (parse-integer text :start i :junk-allowed t)
                     (when v (push v nums))
                     (setf i (if (and pos (> pos i)) pos (1+ i))))
                   (incf i))))
    (setf nums (nreverse nums))
    (if (>= (length nums) 2)
        (values (first nums) (second nums))
        (values nil nil))))

(defun %decode-args (args)
  (cond
    ((hash-table-p args) args)
    ((and (stringp args) (plusp (length (string-trim '(#\Space #\Tab #\Newline) args))))
     (json-protocol:decode args))
    (t (%ht))))

(defun %num (x)
  (cond
    ((realp x) x)
    ((stringp x)
     (let ((n (ignore-errors (parse-number x))))
       (if (realp n) n (error "not a number: ~s" x))))
    (t (error "not a number: ~s" x))))

(defun parse-number (s)
  (let* ((trimmed (string-trim '(#\Space #\Tab) s))
         (n (ignore-errors (parse-integer trimmed :junk-allowed t))))
    (or n
        (let ((*read-eval* nil))
          (let ((v (ignore-errors (read-from-string trimmed))))
            (and (realp v) v))))))

(defun add-handler (args)
  (let* ((obj (%decode-args args))
         (a (%num (or (gethash "a" obj) (gethash "x" obj))))
         (b (%num (or (gethash "b" obj) (gethash "y" obj)))))
    (princ-to-string (+ a b))))

(defun %mock-handler ()
  (lambda (backend turns &key &allow-other-keys)
    (declare (ignore backend))
    (let* ((last (car (last turns)))
           (tool-res (and last
                          (find-if #'llm:llm-tool-result-part-p
                                   (llm:llm-turn-parts last)))))
      (cond
        (tool-res
         (let ((n (llm:llm-tool-result-part-content tool-res)))
           (llm:make-llm-response
            :parts (list (llm:make-llm-text-part :text "That's ")
                         (llm:make-llm-text-part :text (or n ""))
                         (llm:make-llm-text-part :text "."))
            :finish-reason :stop)))
        (t
         (let ((user (or (loop for turn in (reverse turns)
                               when (eq (llm:llm-turn-role turn) :user)
                                 return (llm:turn-text turn))
                         "")))
           (multiple-value-bind (a b) (%two-numbers (or user ""))
             (if a
                 (llm:make-llm-response
                  :parts (list (llm:make-llm-tool-call-part
                                :id "add-1" :name "add"
                                :arguments (format nil "{\"a\":~a,\"b\":~a}" a b)))
                  :finish-reason :tool-use)
                 (llm:make-llm-response
                  :parts (list (llm:make-llm-text-part :text "echo: ")
                               (llm:make-llm-text-part :text (or user "")))
                  :finish-reason :stop)))))))))

(defun make-demo-agent (&key (backend :mock))
  "BACKEND is :mock or an llm-protocol backend."
  (let* ((llm-backend (if (eq backend :mock)
                          (llm:make-mock-llm-backend :handler (%mock-handler))
                          backend))
         (agent (agent:make-ai-agent
                 :name "desk"
                 :backend llm-backend
                 :instructions
                 "You are a desk calculator. For arithmetic call the add tool.
Never add numbers yourself. After the tool returns, answer in one short sentence.")))
    (agent:define-agent-tool
        agent "add"
        (:description "Add two numbers and return the sum."
         :parameters (%add-params))
        (args)
      (add-handler args))
    agent))

(defun make-demo-input (text &key (thread "t1") (run "r1"))
  (ag-ui:make-run-agent-input
   :thread-id thread :run-id run
   :messages (list (ag-ui:make-ag-ui-message
                    :id "m-user" :role "user" :content text))))

(defun run-demo-line (text &key agent on-event)
  "Drive one prompt on the event loop. Returns (values render transcript).
   ON-EVENT is (lambda (event transcript)) after each fold."
  (with-tui-runtime
    (let* ((tr (make-transcript))
           (eb event:*event-backend*)
           (el event:*event-loop*)
           (agent (or agent (make-demo-agent)))
           (err nil))
      (transcript-add-user tr text)
      (ag-ui-enc:start-ag-ui-agent-run
       agent (make-demo-input text)
       :on-event (lambda (ev)
                   (apply-ag-ui-event tr ev)
                   (when on-event (funcall on-event ev tr)))
       :callback (lambda (run)
                   (declare (ignore run))
                   (event:stop eb el))
       :error-callback (lambda (c)
                         (setf err c)
                         (apply-ag-ui-event
                          tr (ag-ui:make-run-error-event
                              :message (princ-to-string c)))
                         (event:stop eb el)))
      (event:run eb el :stop-when-idle nil)
      (when err (error err))
      (values (render-transcript tr) tr))))

(defun run-demo-tui (&key agent prompt)
  "Tuition on this thread; libuv event:run on a side thread."
  (with-tui-runtime
    (let* ((eb event:*event-backend*)
           (el event:*event-loop*)
           (agent (or agent (make-demo-agent)))
           (model (paint:make-ag-ui-tui-model :seed-prompt prompt))
           (program (tui:make-program model))
           (n 0)
           (loop-thread nil))
      (setf (paint:model-on-submit model)
            (lambda (text mdl)
              (declare (ignore mdl))
              (incf n)
              (event:wake-call
               eb el
               (lambda ()
                 (ag-ui-enc:start-ag-ui-agent-run
                  agent (make-demo-input text :run (format nil "r~a" n))
                  :on-event (lambda (ev)
                              (paint:send-ag-ui-event program ev))
                  :callback (lambda (run) (declare (ignore run)))
                  :error-callback
                  (lambda (c)
                    (paint:send-ag-ui-event
                     program
                     (ag-ui:make-run-error-event
                      :message (princ-to-string c)))))))))
      (setf loop-thread
            (bt:make-thread
             (lambda ()
               (event:with-event-backend (eb)
                 (event:with-event-loop-var (el)
                   (event:run eb el :stop-when-idle nil))))
             :name "ag-ui-event-loop"))
      (unwind-protect
           (paint:run-ag-ui-tui :program program)
        (ignore-errors (event:stop eb el))
        (when (and loop-thread (bt:thread-alive-p loop-thread))
          (bt:join-thread loop-thread))))))

(defun %tty-p ()
  (and (interactive-stream-p *query-io*)
       (interactive-stream-p *standard-output*)))

(defun %backend-from-env ()
  (let ((name (string-downcase (or (uiop:getenv "AG_UI_TUI_BACKEND") "mock"))))
    (cond
      ((member name '("openai" "lmstudio") :test #'string=)
       (asdf:load-system "llm-protocol-openai")
       (funcall (find-symbol "MAKE-OPENAI-COMPAT-BACKEND"
                             (find-package '#:llm-protocol-openai))))
      (t :mock))))

(defun %prompt-from-env (&optional default)
  (or (uiop:getenv "AG_UI_TUI_PROMPT")
      default))

(defun main (&key line-mode backend prompt)
  (let* ((line (or line-mode
                   (uiop:getenv "AG_UI_TUI_LINE")
                   (not (%tty-p))))
         (backend (or backend (%backend-from-env)))
         (agent (make-demo-agent :backend backend))
         (prompt (or prompt (%prompt-from-env)
                     (and line "What is 17 plus 25?"))))
    (if line
        (let ((verbose (uiop:getenv "AG_UI_TUI_VERBOSE")))
          (multiple-value-bind (view tr)
              (run-demo-line prompt
                             :agent agent
                             :on-event (and verbose
                                            (lambda (ev transcript)
                                              (declare (ignore ev))
                                              (format t "~%~a~%" (render-transcript transcript))
                                              (force-output))))
            (declare (ignore tr))
            (format t "~a~%" view)
            view))
        (run-demo-tui :agent agent :prompt prompt))))
