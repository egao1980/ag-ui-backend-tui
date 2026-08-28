(defpackage #:ag-ui-backend-tui/demo
  (:use #:cl #:ag-ui-backend-tui)
  (:local-nicknames (#:ag-ui #:ag-ui-protocol)
                    (#:agent #:ai-agent-protocol)
                    (#:ag-ui-enc #:ai-agent-protocol/ag-ui)
                    (#:event #:event-protocol)
                    (#:llm #:llm-protocol)
                    (#:paint #:ag-ui-backend-tui/tuition)
                    (#:tui #:tuition)
                    (#:bt #:bordeaux-threads))
  (:export #:make-demo-agent
           #:make-demo-input
           #:run-demo-line
           #:run-demo-tui
           #:main))

(in-package #:ag-ui-backend-tui/demo)
