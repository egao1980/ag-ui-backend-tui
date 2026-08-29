(defsystem "ag-ui-backend-tui"
  :version "0.1.0"
  :description "AG-UI transcript reducer + optional tuition TUI (events only, no agent core)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("ag-ui-protocol"
               "ag-ui-protocol/client"
               "event-protocol"
               "event-backend-libuv"
               "http-protocol"
               "http-backend-async")
  :properties (:cl-repo (:ci (:with ("dissect"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "transcript")
               (:file "runtime"))
  :in-order-to ((test-op (test-op "ag-ui-backend-tui/tests"))))

(defsystem "ag-ui-backend-tui/tuition"
  :version "0.1.0"
  :description "Tuition TEA paint for ag-ui-backend-tui (optional; not in default test-op)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("ag-ui-backend-tui" "tuition")
  :serial t
  :pathname "src"
  :components ((:file "tuition-package")
               (:file "program")))

(defsystem "ag-ui-backend-tui/demo"
  :version "0.1.0"
  :description "Interactive AG-UI TUI demo (ai-agent → encoder → tuition)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("ag-ui-backend-tui"
               "ag-ui-backend-tui/tuition"
               "ai-agent-protocol"
               "ai-agent-protocol/ag-ui"
               "llm-protocol"
               "json-protocol"
               "json-backend-jzon"
               "bordeaux-threads")
  :properties (:cl-repo (:ci (:with ("http-encoding-brotli" "http-encoding-zstd"))))
  :serial t
  :pathname "src"
  :components ((:file "demo-package")
               (:file "demo"))
  :in-order-to ((test-op (test-op "ag-ui-backend-tui/demo/tests")))))

(defsystem "ag-ui-backend-tui/tests"
  :depends-on ("ag-ui-backend-tui" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "transcript-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))

(defsystem "ag-ui-backend-tui/demo/tests"
  :depends-on ("ag-ui-backend-tui/demo" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "demo-package")
               (:file "demo-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
