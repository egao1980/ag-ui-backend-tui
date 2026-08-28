;;;; AG-UI TUI demo: async agent → encoder → transcript / tuition.
;;;;
;;;;   AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_VERBOSE=1 AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_PROMPT='hello' AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;
;;;; Interactive (tty):  ros -l scripts/demo.lisp
;;;; Live LM Studio:     AG_UI_TUI_BACKEND=openai ros -l scripts/demo.lisp
;;;;
;;;; Does not need CL_SOURCE_REGISTRY — binds the workspace tree from this file.
;;;; Tuition: OCI (once published) / TUITION_PATH / sibling cl-tuition / /tmp/cl-tuition.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&DEMO FAIL: ~A~%" c)
        (uiop:print-backtrace :condition c :stream *error-output*)
        (uiop:quit 1)))

(defun %here ()
  (uiop:pathname-directory-pathname
   (or *load-truename* *compile-file-truename*
       (merge-pathnames "scripts/" (uiop:getcwd)))))

(defun %repo-root ()
  (uiop:pathname-parent-directory-pathname (%here)))

(defun %workspace-root ()
  (uiop:pathname-parent-directory-pathname (%repo-root)))

(defun %tuition-dirs ()
  (remove-duplicates
   (remove nil
           (list (let ((e (uiop:getenv "TUITION_PATH")))
                   (and e (plusp (length e))
                        (uiop:ensure-directory-pathname e)))
                 (probe-file (merge-pathnames "cl-tuition/" (%workspace-root)))
                 (probe-file #p"/tmp/cl-tuition/")))
   :test #'equal))

(defun %bind-workspace-asdf ()
  "First-party siblings live in the workspace tree. Do not require CL_SOURCE_REGISTRY."
  (let ((ws (%workspace-root))
        (repo (%repo-root)))
    (asdf:initialize-source-registry
     `(:source-registry
       (:directory ,repo)
       (:tree ,ws)
       ,@(mapcar (lambda (d)
                   `(:directory ,(uiop:ensure-directory-pathname d)))
                 (%tuition-dirs))
       :inherit-configuration))
    (format *error-output* "~&; demo: workspace=~a~%" ws)))

(defun %register-tuition ()
  (when (asdf:find-system "tuition" nil)
    (return-from %register-tuition t))
  (dolist (dir (%tuition-dirs))
    (let ((asd (probe-file (merge-pathnames "tuition.asd"
                                            (uiop:ensure-directory-pathname dir)))))
      (when asd
        (asdf:load-asd asd)
        (return t)))))

(defun %unquote-dotenv (s)
  (let ((n (length s)))
    (if (and (>= n 2)
             (or (and (char= (char s 0) #\") (char= (char s (1- n)) #\"))
                 (and (char= (char s 0) #\') (char= (char s (1- n)) #\'))))
        (subseq s 1 (1- n))
        s)))

(defun %apply-dotenv-file (path)
  (when (probe-file path)
    (dolist (raw (uiop:split-string (uiop:read-file-string path)
                                    :separator '(#\Newline #\Return)))
      (let ((line (string-trim '(#\Space #\Tab) raw)))
        (when (and (plusp (length line)) (char/= (char line 0) #\#))
          (when (eql (search "export " line) 0)
            (setf line (string-trim '(#\Space #\Tab) (subseq line 7))))
          (let ((eqpos (position #\= line)))
            (when eqpos
              (let ((k (string-trim '(#\Space #\Tab) (subseq line 0 eqpos)))
                    (v (%unquote-dotenv
                        (string-trim '(#\Space #\Tab) (subseq line (1+ eqpos))))))
                (when (and (plusp (length k)) (null (uiop:getenv k)))
                  (setf (uiop:getenv k) v))))))))))

(defun %load-workspace-dotenv ()
  (%apply-dotenv-file (merge-pathnames ".env" (%workspace-root)))
  (%apply-dotenv-file (merge-pathnames ".env" (%repo-root))))

(%bind-workspace-asdf)
(%load-workspace-dotenv)
(ql:quickload '("trivial-channels" "version-string" "serapeum" "cl-base64")
              :silent t)
(%register-tuition)
(asdf:load-asd (merge-pathnames "ag-ui-backend-tui.asd" (%repo-root)))
(asdf:load-system "ag-ui-backend-tui/demo")

(ag-ui-backend-tui/demo:main)
(uiop:quit 0)
