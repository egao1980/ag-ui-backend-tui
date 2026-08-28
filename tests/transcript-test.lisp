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

(deftest state-delta-noop
  (let* ((before (make-transcript))
         (after (apply-ag-ui-event
                 before
                 (ag-ui:make-state-delta-event
                  :delta (list (ag-ui:json-object "op" "replace" "path" "/n" "value" 1))))))
    (ok (eq before after))
    (ok (eq :idle (transcript-status after)))
    (ok (null (transcript-messages after)))))

(deftest unknown-event-no-crash
  (let ((tr (apply-ag-ui-event
             (make-transcript)
             (ag-ui:make-messages-snapshot-event :messages '()))))
    (ok (eq :idle (transcript-status tr)))))

(deftest step-name
  (let ((tr (%fold
             (ag-ui:make-step-started-event :step-name "step-1")
             (ag-ui:make-text-message-content-event :message-id "m" :delta "x"))))
    (ok (equal "step-1" (transcript-step tr)))
    (apply-ag-ui-event tr (ag-ui:make-step-finished-event :step-name "step-1"))
    (ok (null (transcript-step tr)))))
