(defpackage #:ag-ui-backend-tui/tuition
  (:use #:cl #:ag-ui-backend-tui)
  (:local-nicknames (#:tui #:tuition)
                    (#:ag-ui #:ag-ui-protocol))
  (:export #:ag-ui-tui-model
           #:make-ag-ui-tui-model
           #:model-transcript
           #:model-input
           #:model-busy-p
           #:model-on-submit
           #:model-seed-prompt
           #:ag-ui-event-msg
           #:make-ag-ui-event-msg
           #:ag-ui-event-msg-event
           #:submit-request
           #:send-ag-ui-event
           #:run-ag-ui-tui))

(in-package #:ag-ui-backend-tui/tuition)
