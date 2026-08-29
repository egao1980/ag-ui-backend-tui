(in-package #:ag-ui-backend-tui/tests)

(defun %fold (&rest events)
  (let ((tr (make-transcript)))
    (dolist (ev events tr)
      (apply-ag-ui-event tr ev))))

(deftest text-deltas
  (let* ((tr (%fold
              (ag-ui:make-run-started-event :thread-id "t" :run-id "r")
              (ag-ui:make-text-message-start-event :message-id "m1" :role "assistant")
              (ag-ui:make-text-message-content-event :message-id "m1" :delta "hel")
              (ag-ui:make-text-message-content-event :message-id "m1" :delta "lo")
              (ag-ui:make-text-message-end-event :message-id "m1")
              (ag-ui:make-run-finished-event :thread-id "t" :run-id "r")))
         (msg (first (transcript-messages tr)))
         (view (render-transcript tr)))
    (ok (eq :finished (transcript-status tr)))
    (ok (= 1 (length (transcript-messages tr))))
    (ok (equal "hello" (transcript-message-text msg)))
    (ok (transcript-message-ended-p msg))
    (ok (search "desk> hello" view))
    (ok (search "status=finished" view))))

(deftest tool-triad
  (let* ((tr (%fold
              (ag-ui:make-tool-call-start-event :tool-call-id "c1" :tool-call-name "sum")
              (ag-ui:make-tool-call-args-event :tool-call-id "c1" :delta "{\"a\":")
              (ag-ui:make-tool-call-args-event :tool-call-id "c1" :delta "1}")
              (ag-ui:make-tool-call-end-event :tool-call-id "c1")
              (ag-ui:make-tool-call-result-event :message-id "r1"
                                                 :tool-call-id "c1"
                                                 :content "3")))
         (tool (gethash "c1" (transcript-tools tr)))
         (view (render-transcript tr)))
    (ok tool)
    (ok (equal "sum" (transcript-tool-name tool)))
    (ok (equal "{\"a\":1}" (transcript-tool-arguments tool)))
    (ok (equal "3" (transcript-tool-result tool)))
    (ok (eq :result (transcript-tool-status tool)))
    (ok (search "tool sum [c1]" view))
    (ok (search "→ 3" view))))

(deftest cancel-is-error
  (let ((tr (%fold
             (ag-ui:make-run-started-event :thread-id "t" :run-id "r")
             (ag-ui:make-run-error-event :message "canceled" :code "canceled"))))
    (ok (eq :error (transcript-status tr)))
    (ok (equal "canceled" (transcript-error-message tr)))
    (ok (search "error=canceled" (render-transcript tr)))))

(deftest state-snapshot-and-delta-are-applied
  ;; These used to be dropped, so a run's shared state never reached the UI.
  (let ((tr (%fold
             (ag-ui:make-run-started-event :thread-id "t" :run-id "r")
             (ag-ui:make-state-snapshot-event
              :snapshot (ag-ui:json-object "n" 1 "keep" "yes"))
             (ag-ui:make-state-delta-event
              :delta (list (ag-ui:json-object "op" "replace" "path" "/n" "value" 2))))))
    (ok (eql 2 (gethash "n" (transcript-state tr))))
    (ok (equal "yes" (gethash "keep" (transcript-state tr))))
    ;; State is not conversation.
    (ok (null (transcript-messages tr)))
    (ok (search "state " (render-transcript tr)))
    (ok (search "n=2" (render-transcript tr)))
    (ng (search "desk>" (render-transcript tr)))))

(deftest interrupt-outcome-is-not-finished
  (let ((tr (%fold
             (ag-ui:make-run-started-event :thread-id "t" :run-id "r")
             (ag-ui:make-run-interrupted-event
              :thread-id "t" :run-id "r"
              :interrupts (list (ag-ui:make-interrupt
                                 :id "int-1" :reason "tool_call"
                                 :tool-call-id "c1"
                                 :message "Approve danger?"))))))
    (ok (eq :interrupted (transcript-status tr)))
    (ok (= 1 (length (transcript-interrupts tr))))
    (ok (equal "Approve danger?"
               (ag-ui:interrupt-message (first (transcript-interrupts tr)))))
    (let ((view (render-transcript tr)))
      (ok (search "status=interrupted" view))
      (ok (search "? tool_call [c1] Approve danger?" view)))))

(deftest reasoning-renders-on-its-own-line
  (let ((tr (%fold
             (ag-ui:make-run-started-event :thread-id "t" :run-id "r")
             (ag-ui:make-reasoning-message-start-event :message-id "r1")
             (ag-ui:make-reasoning-message-content-event
              :message-id "r1" :delta "weighing")
             (ag-ui:make-reasoning-message-end-event :message-id "r1")
             (ag-ui:make-text-message-start-event :message-id "m1")
             (ag-ui:make-text-message-content-event :message-id "m1" :delta "answer")
             (ag-ui:make-text-message-end-event :message-id "m1"))))
    (ok (= 2 (length (transcript-messages tr))))
    (ok (equal "reasoning" (transcript-message-role (first (transcript-messages tr)))))
    (ok (search "weighing" (render-transcript tr)))
    (ok (search "desk> answer" (render-transcript tr)))))

(deftest unknown-event-no-crash
  (let ((tr (apply-ag-ui-event
             (make-transcript)
             (ag-ui:make-messages-snapshot-event :messages '()))))
    (ok (eq :idle (transcript-status tr)))))

(deftest transcript-history-messages
  (let ((tr (make-transcript)))
    (transcript-add-user tr "hi")
    (apply-ag-ui-event tr (ag-ui:make-text-message-start-event
                           :message-id "a1" :role "assistant"))
    (apply-ag-ui-event tr (ag-ui:make-text-message-content-event
                           :message-id "a1" :delta "hello"))
    (apply-ag-ui-event tr (ag-ui:make-text-message-end-event :message-id "a1"))
    (let ((msgs (transcript-ag-ui-messages tr)))
      (ok (= 2 (length msgs)))
      (ok (equal "user" (ag-ui:ag-ui-message-role (first msgs))))
      (ok (equal "hi" (ag-ui:ag-ui-message-content (first msgs))))
      (ok (equal "assistant" (ag-ui:ag-ui-message-role (second msgs))))
      (ok (equal "hello" (ag-ui:ag-ui-message-content (second msgs)))))))

(deftest transcript-history-tools
  (let ((tr (make-transcript)))
    (transcript-add-user tr "1+2")
    (dolist (ev (list
                 (ag-ui:make-tool-call-start-event :tool-call-id "c1" :tool-call-name "sum")
                 (ag-ui:make-tool-call-args-event :tool-call-id "c1" :delta "{\"a\":1}")
                 (ag-ui:make-tool-call-end-event :tool-call-id "c1")
                 (ag-ui:make-tool-call-result-event :message-id "r1"
                                                    :tool-call-id "c1"
                                                    :content "3")
                 (ag-ui:make-text-message-content-event :message-id "a" :delta "3")))
      (apply-ag-ui-event tr ev))
    (let* ((msgs (transcript-ag-ui-messages tr))
           (roles (mapcar #'ag-ui:ag-ui-message-role msgs)))
      (ok (equal '("user" "assistant" "tool" "assistant") roles))
      (ok (equal "c1" (ag-ui:ag-ui-message-tool-call-id (third msgs))))
      (ok (equal "3" (ag-ui:ag-ui-message-content (third msgs))))
      (let ((input (make-run-agent-input-from-transcript tr :run-id "r2")))
        (ok (equal "r2" (ag-ui:run-agent-input-run-id input)))
        (ok (= 4 (length (ag-ui:run-agent-input-messages input)))))))

(deftest run-agent-input-carries-state
  (let ((tr (%fold
             (ag-ui:make-state-snapshot-event
              :snapshot (ag-ui:json-object "turn" 3)))))
    (let ((input (make-run-agent-input-from-transcript tr :run-id "r9")))
      (ok (eql 3 (gethash "turn" (ag-ui:run-agent-input-state input)))))))

(deftest add-user-line
  (let ((tr (make-transcript)))
    (transcript-add-user tr "hi")
    (ok (= 1 (length (transcript-messages tr))))
    (ok (equal "user" (transcript-message-role (first (transcript-messages tr)))))
    (ok (search "you> hi" (render-transcript tr)))))

(deftest error-log-redirect
  (let ((p (merge-pathnames
            (format nil "ag-ui-tui-test-~a.log" (get-universal-time))
            uiop:*temporary-directory*)))
    (unwind-protect
         (progn
           (when (probe-file p) (delete-file p))
           (call-with-tui-error-log
            p
            (lambda ()
              (format *error-output* "tui-log-probe~%")
              (warn "tui-log-warn")
              (finish-output *error-output*)
              (call-with-tui-error-log
               nil
               (lambda ()
                 (format *error-output* "tui-log-nested~%")
                 (finish-output *error-output*)))))
           (let ((text (uiop:read-file-string p)))
             (ok (search "tui-log-probe" text))
             (ok (search "tui-log-warn" text))
             (ok (search "tui-log-nested" text))))
      (ignore-errors (delete-file p)))))

(deftest step-name
  (let ((tr (%fold
             (ag-ui:make-step-started-event :step-name "step-1")
             (ag-ui:make-text-message-content-event :message-id "m" :delta "x"))))
    (ok (equal "step-1" (transcript-step tr)))
    (apply-ag-ui-event tr (ag-ui:make-step-finished-event :step-name "step-1"))
    (ok (null (transcript-step tr)))))
