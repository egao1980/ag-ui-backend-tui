(defpackage #:ag-ui-backend-tui
  (:use #:cl)
  (:local-nicknames (#:ag-ui #:ag-ui-protocol)
                    (#:event #:event-protocol)
                    (#:http #:http-protocol))
  (:export #:transcript
           #:make-transcript
           #:transcript-p
           #:transcript-status
           #:transcript-error-message
           #:transcript-step
           #:transcript-messages
           #:transcript-tools
           #:transcript-message
           #:make-transcript-message
           #:transcript-message-id
           #:transcript-message-role
           #:transcript-message-text
           #:transcript-message-ended-p
           #:transcript-tool
           #:make-transcript-tool
           #:transcript-tool-id
           #:transcript-tool-name
           #:transcript-tool-arguments
           #:transcript-tool-result
           #:transcript-tool-status
           #:apply-ag-ui-event
           #:transcript-add-user
           #:render-transcript
           #:with-tui-runtime
           #:tui-error-log-path
           #:call-with-tui-error-log
           #:with-tui-error-log))

(in-package #:ag-ui-backend-tui)
