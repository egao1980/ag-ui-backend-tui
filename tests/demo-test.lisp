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

(deftest resume-verdict-words
  (ok (eq t (resume-verdict "Y")))
  (ok (eq t (resume-verdict " approve ")))
  (ok (eq nil (resume-verdict "n")))
  (ok (eq :not-a-verdict (resume-verdict "17 plus 25"))))

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
