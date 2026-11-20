(in-package #:ag-ui-backend-tui/demo/tests)

(deftest line-mode-add-tool
  (multiple-value-bind (view tr session)
      (run-demo-line "What is 17 plus 25?")
    (declare (ignore session))
    (ok (search "That's 42." view))
    (ok (search "tool add" view))
    (ok (search "…>" view))
    (ok (eq :finished (ag-ui-backend-tui:transcript-status tr)))))

(deftest line-mode-echo
  (multiple-value-bind (view tr)
      (run-demo-line "hello there")
    (declare (ignore tr))
    (ok (search "echo: hello there" view))
    (ok (search "…> no numbers" view))))

(deftest live-settings-leave-room-for-answer
  (let* ((s (ag-ui-backend-tui/demo::%demo-settings))
         (llm (agent:agent-settings-llm s)))
    (ok (>= (llm-protocol:llm-settings-max-tokens llm) 2048))
    (let ((extra (llm-protocol:llm-settings-extra llm)))
      (ok (eq nil (getf extra :enable-thinking)))
      (ok (eq nil (getf (getf extra :chat-template-kwargs) :enable-thinking))))))

(deftest resume-verdict-words
  (ok (eq t (resume-verdict "Y")))
  (ok (eq t (resume-verdict " approve ")))
  (ok (eq nil (resume-verdict "n")))
  (ok (eq :not-a-verdict (resume-verdict "17 plus 25")))
  (ok (eq :always (resume-verdict "a")))
  (ok (eq :always (resume-verdict "Always")))
  (ok (eq :reject-all (resume-verdict "r")))
  (ok (eq :reject-all (resume-verdict "reject all")))
  (multiple-value-bind (v fb) (resume-verdict "n: use src/ instead")
    (ok (eq nil v))
    (ok (equal "use src/ instead" fb)))
  (multiple-value-bind (v fb) (resume-verdict "reject all, stop editing")
    (ok (eq :reject-all v))
    (ok (equal "stop editing" fb)))
  (ok (null (nth-value 1 (resume-verdict "n")))))

(defun %paused-transcript ()
  (let ((session (make-demo-session
                  :agent (make-demo-agent :backend :mock :approve t))))
    (nth-value 1 (run-demo-line "What is 17 plus 25?"
                                :session session :auto-approve nil))))

(defun %payloads (input)
  (mapcar #'ag-ui:resume-payload (ag-ui:run-agent-input-resume input)))

(deftest resume-input-replies
  (let ((tr (%paused-transcript)))
    (flet ((payload (&rest args)
             (first (%payloads (apply #'make-resume-input tr args))))
           (key (h k) (gethash k h :absent)))
      (let ((p (payload :approved :always)))
        (ok (eq t (key p "approved")))
        (ok (eq t (key p "always"))))
      (let ((p (payload :approved nil :feedback "No.")))
        (ok (null (key p "approved")))
        (ok (equal "No." (key p "feedback"))))
      (let ((p (payload :approved :reject-all)))
        (ok (null (key p "approved")))
        (ok (eq t (key p "rejectAll"))))
      (let ((p (payload :approved t)))
        (ok (eq t (key p "approved")))
        (ok (eq :absent (key p "always")))))))

(deftest gated-add-auto-approves
  (let* ((agent (make-demo-agent :backend :mock :approve t))
         (session (make-demo-session :agent agent)))
    (multiple-value-bind (view tr sess)
        (run-demo-line "What is 17 plus 25?"
                       :session session
                       :auto-approve t)
      (declare (ignore sess))
      (ok (search "That's 42." view))
      (ok (eq :finished (ag-ui-backend-tui:transcript-status tr)))
      (ok (eq :stop (agent:agent-run-finish-reason
                     (demo-session-last-run session)))))))

(deftest gated-add-pauses-without-auto-approve
  (let* ((agent (make-demo-agent :backend :mock :approve t))
         (session (make-demo-session :agent agent)))
    (multiple-value-bind (view tr sess)
        (run-demo-line "What is 17 plus 25?"
                       :session session
                       :auto-approve nil)
      (declare (ignore sess))
      (ok (eq :interrupted (ag-ui-backend-tui:transcript-status tr)))
      (ok (plusp (length (ag-ui-backend-tui:transcript-interrupts tr))))
      (ok (search "status=interrupted" view))
      (ok (search "? tool_call" view)))))
