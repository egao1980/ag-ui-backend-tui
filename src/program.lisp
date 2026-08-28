(in-package #:ag-ui-backend-tui/tuition)

;;; Tuition TEA paint. Cross-thread: libuv side calls SEND-AG-UI-EVENT.
;;; Never run http:request / event:run on the tuition thread.

(defclass ag-ui-event-msg ()
  ((event :initarg :event :reader ag-ui-event-msg-event)))

(defun make-ag-ui-event-msg (event)
  (make-instance 'ag-ui-event-msg :event event))

(defclass ag-ui-tui-model ()
  ((transcript :initarg :transcript :accessor model-transcript
               :initform (make-transcript))))

(defun make-ag-ui-tui-model (&key transcript)
  (make-instance 'ag-ui-tui-model
                 :transcript (or transcript (make-transcript))))

(defun send-ag-ui-event (program event)
  "Hop an AG-UI event onto the tuition program (safe from the event-loop thread)."
  (tui:send program (make-ag-ui-event-msg event)))

(defmethod tui:init ((model ag-ui-tui-model))
  (declare (ignore model))
  nil)

(defmethod tui:update-message ((model ag-ui-tui-model) (msg ag-ui-event-msg))
  (apply-ag-ui-event (model-transcript model) (ag-ui-event-msg-event msg))
  (values model nil))

(defmethod tui:update-message ((model ag-ui-tui-model) (msg tui:key-msg))
  (let ((key (tui:key-msg-key msg)))
    (if (and (characterp key) (char= key #\q))
        (values model (tui:quit-cmd))
        (values model nil))))

(defmethod tui:view ((model ag-ui-tui-model))
  (render-transcript (model-transcript model)))

(defun run-ag-ui-tui (&key model)
  "Block on the tuition main loop. Caller owns the event-protocol loop on another thread."
  (tui:run (tui:make-program (or model (make-ag-ui-tui-model)))))
