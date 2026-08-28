(defpackage #:ag-ui-backend-tui/tuition
  (:use #:cl #:ag-ui-backend-tui)
  (:local-nicknames (#:tui #:tuition)
                    (#:ag-ui #:ag-ui-protocol))
  (:export #:ag-ui-tui-model
           #:make-ag-ui-tui-model
           #:ag-ui-event-msg
           #:make-ag-ui-event-msg
           #:ag-ui-event-msg-event
           #:send-ag-ui-event
           #:run-ag-ui-tui))

(in-package #:ag-ui-backend-tui/tuition)
