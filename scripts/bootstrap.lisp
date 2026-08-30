;;;; This checkout + first-party siblings + ./.cl-repository.
;;;; Product backends (e.g. ws-backend-websocket-driver) are not tree-walked.

(defparameter *tui-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname
    (or *load-truename* *compile-file-truename* (uiop:getcwd)))))

(defun %env-dir (name)
  (let ((v (uiop:getenv name)))
    (when (and v (plusp (length v)))
      (let ((p (probe-file v)))
        (and p (uiop:ensure-directory-pathname p))))))

(defun %find-workspace (start)
  (loop for dir = (uiop:ensure-directory-pathname start)
          then (uiop:pathname-parent-directory-pathname dir)
        for prev = nil then dir
        until (or (null dir) (equal dir prev))
        when (or (probe-file (merge-pathnames ".lisp-workspace/" dir))
                 (probe-file (merge-pathnames "system-index.txt" dir)))
          return dir
        finally (return nil)))

(defparameter *workspace-root*
  (or (%find-workspace *tui-root*)
      (uiop:pathname-parent-directory-pathname *tui-root*)))

(defparameter *%first-party-dirs*
  '("ag-ui-protocol" "ag-ui-backend-tui" "ai-agent-protocol"
    "llm-protocol" "llm-protocol-openai" "llm-backend-llama-cpp" "llama-cpp"
    "json-protocol" "json-patch"
    "event-protocol" "event-backend-libuv" "cl-stack-executors"
    "http-protocol" "http-backend-async" "http-encoding-chipz"
    "http-encoding-brotli" "http-encoding-zstd"
    "cl-stack-brotli" "cl-stack-zstd"
    "ws-protocol" "sse-protocol" "quri" "cl-idna"
    "io-protocol" "log-protocol" "serdes-protocol"
    "schema-protocol" "schema-protocol-json"))

(defun %first-party-dirs ()
  (let ((ws *workspace-root*))
    (when ws
      (loop for name in *%first-party-dirs*
            for dir = (probe-file (merge-pathnames (format nil "~a/" name) ws))
            when dir
              collect (uiop:ensure-directory-pathname dir)))))

(defun %client-dest ()
  (or (%env-dir "CL_REPOSITORY_DEST")
      (uiop:ensure-directory-pathname
       (merge-pathnames ".cl-repository/" *tui-root*))))

(defun %client-asd ()
  (or (directory (merge-pathnames "**/cl-repository-client.asd" (%client-dest)))
      (let ((d (%env-dir "CL_REPOSITORY_CLIENT_DIR")))
        (when d (directory (merge-pathnames "**/cl-repository-client.asd" d))))))

(defun %load-sibling-asds ()
  (dolist (dir (%first-party-dirs))
    (dolist (asd (directory (merge-pathnames "*.asd" dir)))
      (asdf:load-asd asd))))

(defun %oci-systems-root ()
  (let* ((pkg (find-package '#:cl-repository-client/installer))
         (fn (and pkg (find-symbol "SYSTEMS-ROOT" pkg))))
    (when (and fn (fboundp fn))
      (funcall fn))))

(defun %bind-tui-asdf (&key (oci-root nil oci-root-p))
  "Siblings first, then OCI. Do not let configure-asdf prepend systems-root over checkouts."
  (let ((dest (%client-dest))
        (dirs (%first-party-dirs))
        (oci (if oci-root-p oci-root (%oci-systems-root))))
    (unless (%client-asd)
      (error "cl-repository-client not found — run ./scripts/setup-client.sh"))
    (asdf:initialize-source-registry
     `(:source-registry
       (:directory ,*tui-root*)
       ,@(mapcar (lambda (d) `(:directory ,d)) dirs)
       ,@(when (and oci (probe-file oci)) `((:tree ,oci)))
       (:tree ,dest)
       :ignore-inherited-configuration))
    (%load-sibling-asds)
    (asdf:load-asd (merge-pathnames "ag-ui-backend-tui.asd" *tui-root*))
    (format *error-output* "~&; tui: root=~a~%;      dest=~a~%" *tui-root* dest)))

(setf asdf:*compile-file-failure-behaviour* :warn)
(%bind-tui-asdf)
#+sbcl
(handler-bind ((sb-ext:defconstant-uneql #'continue))
  (asdf:load-system "cl-repository-client" :verbose nil))
#-sbcl
(asdf:load-system "cl-repository-client" :verbose nil)
(cl-repository-client/asdf-integration:configure-asdf-source-registry)
(%bind-tui-asdf) ; siblings back in front after client prepends systems-root

(defun load-tui-init-files ()
  "Load cl-repo-init.lisp. Skip vllm-cpp (preload can SIGKILL)."
  (let ((root (cl-repository-client/installer:systems-root)))
    (when (probe-file root)
      (dolist (system-dir (uiop:subdirectories root))
        (let ((name (car (last (pathname-directory system-dir)))))
          (unless (or (string-equal name "vllm-cpp")
                      (string-equal name "llama-cpp"))
            (dolist (version-dir (uiop:subdirectories system-dir))
              (let ((init (merge-pathnames "cl-repo-init.lisp" version-dir)))
                (when (probe-file init)
                  (load init))))))))))

(load-tui-init-files)
