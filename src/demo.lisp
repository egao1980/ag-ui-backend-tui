(in-package #:ag-ui-backend-tui/demo)

;;; Glue: ai-agent → /ag-ui encoder → transcript / tuition.
;;; Core TUI stays AG-UI-only. This system is the product demo.

(defun %env (name)
  (let ((v (uiop:getenv name)))
    (and v (plusp (length v)) v)))

(defun %env-flag (name)
  (let ((v (%env name)))
    (and v (member (string-downcase (string-trim '(#\Space #\Tab) v))
                   '("1" "true" "yes" "on") :test #'string=))))

(defun %parse-int-env (name default)
  (let ((v (%env name)))
    (or (and v (ignore-errors (parse-integer v :junk-allowed t))) default)))

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
            :parts (list (llm:make-llm-thinking-part :text "tool returned")
                         (llm:make-llm-text-part :text "That's ")
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
                  :parts (list (llm:make-llm-thinking-part
                                :text "need the add tool")
                               (llm:make-llm-tool-call-part
                                :id "add-1" :name "add"
                                :arguments (format nil "{\"a\":~a,\"b\":~a}" a b)))
                  :finish-reason :tool-use)
                 (llm:make-llm-response
                  :parts (list (llm:make-llm-thinking-part :text "no numbers")
                               (llm:make-llm-text-part :text "echo: ")
                               (llm:make-llm-text-part :text (or user "")))
                  :finish-reason :stop)))))))))

(defun %tools-p (backend)
  (or (eq backend :mock)
      (and (not (keywordp backend))
           (ignore-errors (llm:backend-supports-p backend :tools)))))

(defun %approve-tools-p ()
  (%env-flag "AG_UI_TUI_APPROVE"))

(defun make-demo-agent (&key (backend :mock) (approve (%approve-tools-p)))
  "BACKEND is :mock or an llm-protocol backend.
   APPROVE gates the add tool (HITL interrupt). llama.cpp has no tools."
  (let* ((llm-backend (if (eq backend :mock)
                          (llm:make-mock-llm-backend :handler (%mock-handler))
                          backend))
         (tools-p (%tools-p backend))
         (agent (agent:make-ai-agent
                 :name "desk"
                 :backend llm-backend
                 :instructions
                 (if tools-p
                     "You are a desk assistant. The only tool is add (two numbers).
Call add only for arithmetic. If asked what tools exist, answer in text — do not call add.
After a tool returns, answer in one short sentence. Do not narrate your reasoning."
                     "You are a terse desk assistant. Answer in one or two sentences."))))
    (when tools-p
      (agent:define-agent-tool
          agent "add"
          (:description "Add two numbers and return the sum."
           :parameters (%add-params)
           :approval approve)
          (args)
        (add-handler args)))
    agent))

(defclass demo-session ()
  ((agent :initarg :agent :accessor demo-session-agent)
   (backend :initarg :backend :accessor demo-session-backend :initform nil)
   (last-run :initform nil :accessor demo-session-last-run)
   (thread-id :initarg :thread-id :accessor demo-session-thread-id
              :initform "t1")
   (n :initform 0 :accessor demo-session-n)
   (settings :initarg :settings :accessor demo-session-settings :initform nil)))

(defun make-demo-session (&key agent backend (thread-id "t1") settings approve)
  (make-instance 'demo-session
                 :agent (or agent (make-demo-agent :backend (or backend :mock)
                                                   :approve approve))
                 :backend backend
                 :thread-id thread-id
                 :settings settings))

(defun close-demo-session (session)
  "Release native engines (llama.cpp Metal aborts if we just exit)."
  (let ((backend (and session (demo-session-backend session)))
        (pkg (find-package '#:llm-backend-llama-cpp)))
    (when (and pkg backend (not (keywordp backend)))
      (let ((class (find-symbol "LLAMA-CPP-BACKEND" pkg))
            (close (find-symbol "CLOSE-LLAMA-CPP-BACKEND" pkg)))
        (when (and class close (typep backend class))
          (ignore-errors (funcall close backend))))))
  session)

(defun %next-run-id (session &optional suffix)
  (incf (demo-session-n session))
  (format nil "r~a~@[-~a~]" (demo-session-n session) suffix))

(defun make-demo-input (source &key (thread "t1") (run "r1") tools)
  "SOURCE is a transcript (full thread) or a user string."
  (if (transcript-p source)
      (make-run-agent-input-from-transcript source :thread-id thread :run-id run
                                            :tools tools)
      (ag-ui:make-run-agent-input
       :thread-id thread :run-id run
       :messages (list (ag-ui:make-ag-ui-message
                        :id "m-user" :role "user" :content source)))))

(defun make-resume-input (tr &key (thread "t1") (run "r2") (approved t))
  "Answer every open interrupt. APPROVED is the payload verdict."
  (make-run-agent-input-from-transcript
   tr :thread-id thread :run-id run
   :resume (mapcar (lambda (int)
                     (ag-ui:make-resume-entry
                      :interrupt-id (ag-ui:interrupt-id int)
                      :payload (ag-ui:json-object "approved" approved)))
                   (transcript-interrupts tr))))

(defun resume-verdict (text)
  "Parse a y/n / yes/no / approve/deny line. NIL if it is ordinary user text."
  (let ((s (string-downcase (string-trim '(#\Space #\Tab #\Newline) (or text "")))))
    (cond
      ((member s '("y" "yes" "approve") :test #'string=) t)
      ((member s '("n" "no" "deny") :test #'string=) nil)
      (t :not-a-verdict))))

(defun %on-event (tr ev &optional extra)
  (apply-ag-ui-event tr ev)
  (when extra (funcall extra ev tr)))

(defun start-demo-resume (session input &key on-event callback error-callback)
  (let ((run (demo-session-last-run session)))
    (unless run
      (error "no paused run to resume"))
    (let ((encoder (ag-ui-enc:make-ag-ui-encoder
                    :thread-id (or (ag-ui:run-agent-input-thread-id input) "t1")
                    :run-id (or (ag-ui:run-agent-input-run-id input) "r")
                    :on-event on-event)))
      (dolist (inv (agent:agent-run-pending run))
        (ag-ui-enc:mark-tool-resumed encoder (agent:agent-invocation-id inv)))
      (ag-ui-enc:apply-resume run input)
      (agent:resume-ai-agent-async
       run
       :on-event (lambda (kind payload)
                   (ag-ui-enc:encode-agent-event encoder kind payload))
       :callback (lambda (finished)
                   (setf (demo-session-last-run session) finished)
                   (when callback (funcall callback finished)))
       :error-callback (lambda (c)
                         (ag-ui-enc:encode-agent-event encoder :error c)
                         (when error-callback (funcall error-callback c)))))))

(defun start-demo-turn (session tr &key on-event callback error-callback
                       (resume-approved :not-a-verdict))
  "Start a run, or resume if TR is interrupted and RESUME-APPROVED is a boolean.
   ON-EVENT is the raw AG-UI sink — callers fold or hop; this does not apply."
  (let* ((thread (demo-session-thread-id session))
         (ok (lambda (run)
               (setf (demo-session-last-run session) run)
               (when callback (funcall callback run))))
         (err error-callback))
    (if (and (eq (transcript-status tr) :interrupted)
             (demo-session-last-run session)
             (not (eq resume-approved :not-a-verdict)))
        (start-demo-resume
         session
         (make-resume-input tr :thread thread
                            :run (%next-run-id session "resume")
                            :approved resume-approved)
         :on-event on-event :callback ok :error-callback err)
        (ag-ui-enc:start-ag-ui-agent-run
         (demo-session-agent session)
         (make-demo-input tr :thread thread :run (%next-run-id session))
         :settings (demo-session-settings session)
         :on-event on-event :callback ok :error-callback err))))

(defun run-demo-line (text &key agent session on-event (auto-approve t))
  "Drive one prompt on the event loop. Returns (values render transcript session).
   AUTO-APPROVE answers a tool-call interrupt so line mode can finish."
  (with-tui-runtime
    (let* ((tr (make-transcript))
           (eb event:*event-backend*)
           (el event:*event-loop*)
           (session (or session (make-demo-session :agent agent)))
           (err nil)
           (stop (lambda () (event:stop eb el)))
           (fail (lambda (c)
                   (setf err c)
                   (apply-ag-ui-event
                    tr (ag-ui:make-run-error-event
                        :message (princ-to-string c)))
                   (funcall stop))))
      (transcript-add-user tr text)
      (start-demo-turn
       session tr
       :on-event (lambda (ev) (%on-event tr ev on-event))
       :callback (lambda (run)
                   (if (and auto-approve
                            (eq (agent:agent-run-finish-reason run) :approval)
                            (transcript-interrupts tr))
                       (start-demo-resume
                        session
                        (make-resume-input
                         tr :thread (demo-session-thread-id session)
                         :run (%next-run-id session "resume")
                         :approved t)
                        :on-event (lambda (ev) (%on-event tr ev on-event))
                        :callback (lambda (finished)
                                    (declare (ignore finished))
                                    (funcall stop))
                        :error-callback fail)
                       (funcall stop)))
       :error-callback fail)
      (event:run eb el :stop-when-idle nil)
      (when err (error err))
      (values (render-transcript tr) tr session))))

(defun %ensure-off-loop-stderr ()
  "Submit workers do not inherit the TUI error-log binding unless captured."
  (pushnew 'cl:*error-output* agent:*off-loop-specials*)
  (pushnew 'cl:*trace-output* agent:*off-loop-specials*))

(defun %interrupted-p (session tr)
  (and (eq (transcript-status tr) :interrupted)
       (demo-session-last-run session)
       (transcript-interrupts tr)))

(defun run-demo-tui (&key agent session prompt)
  "Tuition on this thread; libuv event:run on a side thread.
   Redirects *ERROR-OUTPUT* to the TUI error log on every hop thread.
   y/n (or yes/no) answers an open tool-call interrupt instead of a new turn."
  (with-tui-runtime
    (with-tui-error-log ()
      (%ensure-off-loop-stderr)
      (let* ((eb event:*event-backend*)
             (el event:*event-loop*)
             (session (or session (make-demo-session :agent agent)))
             (model (paint:make-ag-ui-tui-model :seed-prompt prompt))
             (program (tui:make-program model))
             (err *error-output*)
             (trc *trace-output*)
             (loop-thread nil))
        (setf (paint:model-on-submit model)
              (lambda (text mdl)
                (let* ((tr (paint:model-transcript mdl))
                       (verdict (resume-verdict text)))
                  (event:wake-call
                   eb el
                   (lambda ()
                     (start-demo-turn
                      session tr
                      :resume-approved (if (%interrupted-p session tr)
                                           verdict
                                           :not-a-verdict)
                      :on-event (lambda (ev)
                                  (paint:send-ag-ui-event program ev))
                      :callback (lambda (run) (declare (ignore run)))
                      :error-callback
                      (lambda (c)
                        (paint:send-ag-ui-event
                         program
                         (ag-ui:make-run-error-event
                          :message (princ-to-string c))))))))))
        (setf loop-thread
              (bt:make-thread
               (lambda ()
                 (let ((*error-output* err)
                       (*trace-output* trc))
                   (event:with-event-backend (eb)
                     (event:with-event-loop-var (el)
                       (event:run eb el :stop-when-idle nil)))))
               :name "ag-ui-event-loop"))
        (unwind-protect
             (paint:run-ag-ui-tui :program program)
          (ignore-errors (event:stop eb el))
          (when (and loop-thread (bt:thread-alive-p loop-thread))
            (bt:join-thread loop-thread)))))))

(defun %tty-p ()
  (and (interactive-stream-p *query-io*)
       (interactive-stream-p *standard-output*)))

(defun %ensure-off-loop-http ()
  "Generate runs on a submit worker — rebind the let-bound HTTP backend."
  (pushnew 'http-protocol:*http-backend* agent:*off-loop-specials*))

(defun %think-p ()
  (%env-flag "AG_UI_TUI_THINK"))

(defun %demo-llm-extra ()
  "Qwen3 / LM Studio spend max_tokens on think and never emit the answer.
   Off unless AG_UI_TUI_THINK=1. Both wire keys — stacks pick one."
  (unless (%think-p)
    '(:chat-template-kwargs (:enable-thinking nil)
      :enable-thinking nil)))

(defun %demo-settings ()
  (agent:make-agent-settings
   :llm (llm:make-llm-settings
         :max-tokens (%parse-int-env "AG_UI_TUI_MAX_TOKENS"
                                     (if (%think-p) 4096 2048))
         :temperature (let ((v (%env "AG_UI_TUI_TEMPERATURE")))
                        (or (and v (let ((*read-eval* nil))
                                     (ignore-errors (read-from-string v))))
                            0.0))
         :extra (%demo-llm-extra))))

(defun %chat-gguf-p (path)
  (let ((n (string-downcase (file-namestring path))))
    (not (or (search "embed" n) (search "mmproj" n)
             (search "clip" n) (search "ocr" n)))))

(defun %list-ggufs (root)
  (when (probe-file root)
    (let ((acc '()))
      (uiop:collect-sub*directories
       (uiop:ensure-directory-pathname root)
       (constantly t) (constantly t)
       (lambda (dir)
         (dolist (p (directory (merge-pathnames "*.gguf" dir)))
           (push p acc))))
      acc)))

(defun find-demo-gguf ()
  "Chat GGUF: LLAMA_MODEL_PATH / LLAMA_CPP_MODEL, else ~/.lmstudio/models."
  (or (%env "LLAMA_MODEL_PATH")
      (%env "LLAMA_CPP_MODEL")
      (let* ((root (merge-pathnames ".lmstudio/models/" (user-homedir-pathname)))
             (files (remove-if-not #'%chat-gguf-p (%list-ggufs root)))
             (prefer '("Qwen3.5-2B-Q4_K_M.gguf"
                       "Qwen3.5-2B-Q4_0.gguf"
                       "Qwen3.5-0.8B-Q4_K_M.gguf"
                       "Qwen3.5-0.8B-Q4_0.gguf")))
        (or (loop for name in prefer
                  for hit = (find name files :test #'string-equal
                                  :key #'file-namestring)
                  when hit return (namestring hit))
            (when files (namestring (first files)))))))

(defun make-llama-cpp-demo-backend ()
  (asdf:load-system "llm-backend-llama-cpp")
  (let ((path (find-demo-gguf)))
    (unless path
      (error "set LLAMA_MODEL_PATH to a chat GGUF (not an embedding model)"))
    (unless (funcall (find-symbol "LLAMA-AVAILABLE-P" (find-package '#:llama-cpp)))
      (error "llama.cpp overlay missing — build llama-cpp or install the OCI native"))
    (funcall (find-symbol "MAKE-LLAMA-CPP-BACKEND"
                          (find-package '#:llm-backend-llama-cpp))
             :model-path path
             :n-ctx (%parse-int-env "LLAMA_N_CTX" 2048))))

(defun %backend-from-env ()
  (let ((name (string-downcase (or (%env "AG_UI_TUI_BACKEND") "mock"))))
    (cond
      ((member name '("openai" "lmstudio") :test #'string=)
       (asdf:load-system "llm-protocol-openai")
       (%ensure-off-loop-http)
       (funcall (find-symbol "MAKE-OPENAI-COMPAT-BACKEND"
                             (find-package '#:llm-protocol-openai))))
      ((member name '("llama-cpp" "llama" "llamacpp") :test #'string=)
       (make-llama-cpp-demo-backend))
      (t :mock))))

(defun %prompt-from-env (&optional default)
  (or (%env "AG_UI_TUI_PROMPT")
      default))

(defun main (&key line-mode backend prompt session)
  (let* ((line (or line-mode
                   (%env "AG_UI_TUI_LINE")
                   (not (%tty-p))))
         (backend (or backend (%backend-from-env)))
         (session (or session
                      (make-demo-session
                       :backend backend
                       :settings (unless (eq backend :mock) (%demo-settings)))))
         (prompt (or prompt (%prompt-from-env)
                     (and line
                          (if (%tools-p backend)
                              "What is 17 plus 25?"
                              "Say hello in five words.")))))
    (unwind-protect
         (if line
             (let ((verbose (%env "AG_UI_TUI_VERBOSE")))
               (multiple-value-bind (view tr sess)
                   (run-demo-line prompt
                                  :session session
                                  :auto-approve (if (%env "AG_UI_TUI_AUTO_APPROVE")
                                                    (%env-flag "AG_UI_TUI_AUTO_APPROVE")
                                                    t)
                                  :on-event (and verbose
                                                 (lambda (ev transcript)
                                                   (declare (ignore ev))
                                                   (format t "~%~a~%" (render-transcript transcript))
                                                   (force-output))))
                 (declare (ignore tr sess))
                 (format t "~a~%" view)
                 view))
             (run-demo-tui :session session :prompt prompt))
      (close-demo-session session))))
