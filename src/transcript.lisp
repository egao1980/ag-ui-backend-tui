(in-package #:ag-ui-backend-tui)

;;; Pure AG-UI event reducer. No tuition, no agent-run, no :part.

(defclass transcript-message ()
  ((id :initarg :id :accessor transcript-message-id)
   (role :initarg :role :accessor transcript-message-role :initform "assistant")
   (text :initarg :text :accessor transcript-message-text :initform "")
   (ended-p :initarg :ended-p :accessor transcript-message-ended-p :initform nil)))

(defun make-transcript-message (&key id (role "assistant") (text "") ended-p)
  (make-instance 'transcript-message :id id :role role :text text :ended-p ended-p))

(defclass transcript-tool ()
  ((id :initarg :id :accessor transcript-tool-id)
   (name :initarg :name :accessor transcript-tool-name :initform "")
   (arguments :initarg :arguments :accessor transcript-tool-arguments :initform "")
   (result :initarg :result :accessor transcript-tool-result :initform nil)
   (status :initarg :status :accessor transcript-tool-status :initform :open)))

(defun make-transcript-tool (&key id (name "") (arguments "") result (status :open))
  (make-instance 'transcript-tool :id id :name name :arguments arguments
                                 :result result :status status))

(defclass transcript ()
  ((status :initarg :status :accessor transcript-status :initform :idle)
   (error-message :initarg :error-message :accessor transcript-error-message
                  :initform nil)
   (step :initarg :step :accessor transcript-step :initform nil)
   (messages :initarg :messages :accessor transcript-messages :initform nil)
   (tools :initform (make-hash-table :test #'equal) :accessor transcript-tools)
   (tool-order :initform nil :accessor transcript-tool-order)))

(defun make-transcript ()
  (make-instance 'transcript))

(defun transcript-p (x)
  (typep x 'transcript))

(defun %find-message (tr id)
  (find id (transcript-messages tr) :key #'transcript-message-id :test #'equal))

(defun %ensure-tool (tr id &key name)
  (or (gethash id (transcript-tools tr))
      (let ((tool (make-transcript-tool :id id :name (or name ""))))
        (setf (gethash id (transcript-tools tr)) tool)
        (setf (transcript-tool-order tr)
              (append (transcript-tool-order tr) (list id)))
        tool)))

(defgeneric apply-ag-ui-event (transcript event)
  (:documentation "Fold EVENT into TRANSCRIPT. Returns TRANSCRIPT.
   STATE_DELTA is a wave-1 no-op. Unknown event classes are ignored."))

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:run-started-event))
  (setf (transcript-status tr) :running
        (transcript-error-message tr) nil)
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:run-finished-event))
  (setf (transcript-status tr) :finished)
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:run-error-event))
  (setf (transcript-status tr) :error
        (transcript-error-message tr) (ag-ui:run-error-message ev))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:step-started-event))
  (setf (transcript-step tr) (ag-ui:step-event-name ev))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:step-finished-event))
  (when (equal (transcript-step tr) (ag-ui:step-event-name ev))
    (setf (transcript-step tr) nil))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:text-message-start-event))
  (let ((id (ag-ui:text-message-id ev)))
    (unless (%find-message tr id)
      (setf (transcript-messages tr)
            (append (transcript-messages tr)
                    (list (make-transcript-message
                           :id id
                           :role (or (ag-ui:text-message-role ev) "assistant")))))))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:text-message-content-event))
  (let* ((id (ag-ui:text-message-id ev))
         (msg (or (%find-message tr id)
                  (let ((m (make-transcript-message :id id)))
                    (setf (transcript-messages tr)
                          (append (transcript-messages tr) (list m)))
                    m))))
    (setf (transcript-message-text msg)
          (concatenate 'string (transcript-message-text msg)
                       (or (ag-ui:text-message-delta ev) ""))))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:text-message-end-event))
  (let ((msg (%find-message tr (ag-ui:text-message-id ev))))
    (when msg
      (setf (transcript-message-ended-p msg) t)))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:tool-call-start-event))
  (let ((tool (%ensure-tool tr (ag-ui:tool-call-id ev)
                            :name (ag-ui:tool-call-name ev))))
    (setf (transcript-tool-name tool) (or (ag-ui:tool-call-name ev) "")
          (transcript-tool-status tool) :open))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:tool-call-args-event))
  (let ((tool (%ensure-tool tr (ag-ui:tool-call-id ev))))
    (setf (transcript-tool-arguments tool)
          (concatenate 'string (transcript-tool-arguments tool)
                       (or (ag-ui:tool-call-delta ev) ""))))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:tool-call-end-event))
  (let ((tool (%ensure-tool tr (ag-ui:tool-call-id ev))))
    (setf (transcript-tool-status tool) :ended))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:tool-call-result-event))
  (let ((tool (%ensure-tool tr (ag-ui:tool-call-id ev))))
    (setf (transcript-tool-result tool) (or (ag-ui:tool-call-result-content ev) "")
          (transcript-tool-status tool) :result))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:state-delta-event))
  (declare (ignore ev))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:state-snapshot-event))
  (declare (ignore ev))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:messages-snapshot-event))
  (declare (ignore ev))
  tr)

(defmethod apply-ag-ui-event ((tr transcript) (ev ag-ui:ag-ui-event))
  (declare (ignore ev))
  tr)

(defun %tool-call-hash (tool)
  (ag-ui:json-object
   "id" (transcript-tool-id tool)
   "type" "function"
   "function" (ag-ui:json-object
               "name" (or (transcript-tool-name tool) "")
               "arguments" (or (transcript-tool-arguments tool) "{}"))))

(defun %flush-completed-tools (tr emitted out)
  (dolist (id (transcript-tool-order tr) out)
    (let ((tool (gethash id (transcript-tools tr))))
      (when (and tool
                 (not (gethash id emitted))
                 (eq (transcript-tool-status tool) :result))
        (setf (gethash id emitted) t)
        (push (ag-ui:make-ag-ui-message
               :id (format nil "asst-~a" id)
               :role "assistant"
               :tool-calls (vector (%tool-call-hash tool)))
              out)
        (push (ag-ui:make-ag-ui-message
               :id (format nil "tool-~a" id)
               :role "tool"
               :name (transcript-tool-name tool)
               :tool-call-id id
               :content (or (transcript-tool-result tool) ""))
              out)))))

(defun transcript-ag-ui-messages (tr)
  "Full thread as AG-UI messages (user/assistant text + completed tool triad).
   Clients send this as `run-agent-input.messages` on every turn."
  (let ((emitted (make-hash-table :test #'equal))
        (out '())
        (seen-p nil))
    (dolist (msg (transcript-messages tr))
      (let ((role (transcript-message-role msg))
            (text (or (transcript-message-text msg) "")))
        (cond
          ((equal role "user")
           (when seen-p
             (setf out (%flush-completed-tools tr emitted out)))
           (when (plusp (length text))
             (push (ag-ui:make-ag-ui-message
                    :id (transcript-message-id msg)
                    :role "user"
                    :content text)
                   out)))
          (t
           (setf out (%flush-completed-tools tr emitted out))
           (when (plusp (length text))
             (push (ag-ui:make-ag-ui-message
                    :id (transcript-message-id msg)
                    :role (or role "assistant")
                    :content text)
                   out))))
      (setf seen-p t))
    (nreverse (%flush-completed-tools tr emitted out))))

(defun make-run-agent-input-from-transcript (tr &key (thread-id "t1") (run-id "r1"))
  "Reusable client helper: transcript → `run-agent-input` with full history."
  (ag-ui:make-run-agent-input
   :thread-id thread-id
   :run-id run-id
   :messages (transcript-ag-ui-messages tr)))

(defun transcript-add-user (tr text)
  "Local user line (not an AG-UI event). TUI / demo call this on submit."
  (setf (transcript-messages tr)
        (append (transcript-messages tr)
                (list (make-transcript-message
                       :id (format nil "user-~a" (length (transcript-messages tr)))
                       :role "user"
                       :text (or text "")
                       :ended-p t))))
  tr)

(defun render-transcript (tr)
  "Plain-text view of TR for tests / fallback paint. No tty."
  (with-output-to-string (s)
    (format s "status=~(~a~)" (transcript-status tr))
    (when (transcript-step tr)
      (format s " step=~a" (transcript-step tr)))
    (when (transcript-error-message tr)
      (format s " error=~a" (transcript-error-message tr)))
    (terpri s)
    (dolist (msg (transcript-messages tr))
      (format s "~a> ~a~%"
              (if (equal (transcript-message-role msg) "user") "you" "desk")
              (transcript-message-text msg)))
    (dolist (id (transcript-tool-order tr))
      (let ((tool (gethash id (transcript-tools tr))))
        (when tool
          (format s "tool ~a [~a] ~a"
                  (transcript-tool-name tool) id
                  (transcript-tool-arguments tool))
          (when (transcript-tool-result tool)
            (format s " → ~a" (transcript-tool-result tool)))
          (terpri s))))))
