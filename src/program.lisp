(in-package #:ag-ui-backend-tui/tuition)

;;; Tuition TEA paint. Cross-thread: libuv side calls SEND-AG-UI-EVENT.
;;; Never run http:request / event:run on the tuition thread.

(defclass ag-ui-event-msg ()
  ((event :initarg :event :reader ag-ui-event-msg-event)))

(defun make-ag-ui-event-msg (event)
  (make-instance 'ag-ui-event-msg :event event))

(defclass submit-request ()
  ((text :initarg :text :reader submit-request-text)))

(defclass ag-ui-tui-model ()
  ((transcript :initarg :transcript :accessor model-transcript
               :initform (make-transcript))
   (input :initform "" :accessor model-input)
   (busy-p :initform nil :accessor model-busy-p)
   (on-submit :initarg :on-submit :initform nil :accessor model-on-submit)
   (seed-prompt :initarg :seed-prompt :initform nil :accessor model-seed-prompt)))

(defun make-ag-ui-tui-model (&key transcript seed-prompt on-submit)
  (make-instance 'ag-ui-tui-model
                 :transcript (or transcript (make-transcript))
                 :seed-prompt seed-prompt
                 :on-submit on-submit))

(defun send-ag-ui-event (program event)
  "Hop an AG-UI event onto the tuition program (safe from the event-loop thread)."
  (tui:send program (make-ag-ui-event-msg event)))

(defun %chop (s)
  (if (plusp (length s))
      (subseq s 0 (1- (length s)))
      s))

(defun %ctrl-p (msg)
  (tui:mod-contains (tui:key-event-mod msg) tui:+mod-ctrl+))

(defun %try-submit (model text)
  (let ((text (string-trim '(#\Space #\Tab #\Newline) (or text ""))))
    (cond
      ((or (zerop (length text)) (model-busy-p model))
       (values model nil))
      (t
       (setf (model-input model) ""
             (model-busy-p model) t)
       (transcript-add-user (model-transcript model) text)
       (when (model-on-submit model)
         (funcall (model-on-submit model) text model))
       (values model nil)))))

(defmethod tui:init ((model ag-ui-tui-model))
  (let ((seed (model-seed-prompt model)))
    (when (and seed (plusp (length seed)))
      (setf (model-seed-prompt model) nil)
      (lambda ()
        (make-instance 'submit-request :text seed)))))

(defmethod tui:update-message ((model ag-ui-tui-model) (msg ag-ui-event-msg))
  (let ((ev (ag-ui-event-msg-event msg)))
    (apply-ag-ui-event (model-transcript model) ev)
    (let ((ty (ag-ui:ag-ui-event-type ev)))
      (when (or (equal ty "RUN_FINISHED") (equal ty "RUN_ERROR"))
        (setf (model-busy-p model) nil))))
  (values model nil))

(defmethod tui:update-message ((model ag-ui-tui-model) (msg submit-request))
  (%try-submit model (submit-request-text msg)))

(defmethod tui:update-message ((model ag-ui-tui-model) (msg tui:key-press-msg))
  (let ((key (tui:key-event-code msg))
        (text (tui:key-event-text msg)))
    (cond
      ((or (eq key :escape)
           (and (%ctrl-p msg) (or (eql key #\c) (eql key #\C) (eql key #\d) (eql key #\D))))
       (values model (tui:quit-cmd)))
      ((and (or (eql key #\q) (eql key #\Q))
            (zerop (length (model-input model)))
            (not (model-busy-p model)))
       (values model (tui:quit-cmd)))
      ((or (eq key :enter) (eql key #\Return) (eql key #\Newline))
       (%try-submit model (model-input model)))
      ((or (eq key :backspace) (eq key :delete) (eql key #\Backspace))
       (setf (model-input model) (%chop (model-input model)))
       (values model nil))
      ((and (stringp text) (plusp (length text)) (not (%ctrl-p msg)))
       (setf (model-input model)
             (concatenate 'string (model-input model) text))
       (values model nil))
      ((and (characterp key) (graphic-char-p key) (not (%ctrl-p msg)))
       (setf (model-input model)
             (concatenate 'string (model-input model) (string key)))
       (values model nil))
      (t
       (values model nil)))))

(defmethod tui:view ((model ag-ui-tui-model))
  (tui:make-view
   (with-output-to-string (s)
     (format s "ag-ui-tui  q=quit  enter=send~%")
     (format s "~a~%" (render-transcript (model-transcript model)))
     (format s "> ~a~a"
             (model-input model)
             (if (model-busy-p model) "  [busy]" "")))
   :alt-screen t
   :window-title "ag-ui-tui"))

(defun run-ag-ui-tui (&key model program)
  "Block on the tuition main loop. Caller owns the event-protocol loop on another thread."
  (tui:run (or program (tui:make-program (or model (make-ag-ui-tui-model))))))
