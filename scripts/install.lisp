;;;; Install .asd deps from ghcr.io/egao1980/cl-systems (force latest tags).
;;;;   ./scripts/setup-client.sh
;;;;   ros -l scripts/install.lisp
;;;;
;;;; Local first-party siblings stay on ASDF (in-progress checkouts). Missing
;;;; names come from GHCR. Tuition + its pins are force-pulled (latest published).

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&INSTALL FAIL: ~A~%" c)
        (uiop:print-backtrace :condition c :stream *error-output*)
        (uiop:quit 1)))

(load (merge-pathnames "bootstrap.lisp" *load-truename*))

(asdf:load-system "cl-repository-client")
(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

(defun %install (name &key (also-tests t))
  (format t "~&; install deps for ~a~%" name)
  (cl-repo:ensure-system-dependencies name
                                      :also-tests also-tests
                                      :default-source :oci)
  (cl-repository-client/asdf-integration:configure-asdf-source-registry)
  (%bind-tui-asdf))

(%install "ag-ui-backend-tui" :also-tests t)
(%install "ag-ui-backend-tui/demo" :also-tests nil)

;; Paint kit + its published source-only deps (not first-party siblings).
(format t "~&; install tuition from OCI~%")
(cl-repo:ensure-systems '("tuition" "version-string" "trivial-channels" "serapeum")
                        :default-source :oci
                        :force t)
(cl-repository-client/asdf-integration:configure-asdf-source-registry)
(%bind-tui-asdf)
(load-tui-init-files)

(dolist (n '("tuition" "ag-ui-backend-tui" "ag-ui-backend-tui/demo"))
  (unless (asdf:find-system n nil)
    (error "after install, ASDF cannot find ~a" n)))
(format t "~&; install done (tuition ~a)~%"
        (or (cl-repo:installed-system-version "tuition") "?"))
(uiop:quit 0)
