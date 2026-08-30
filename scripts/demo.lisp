;;;; AG-UI TUI demo: async agent → encoder → transcript / tuition.
;;;;
;;;;   ./scripts/setup-client.sh && ros -l scripts/install.lisp
;;;;   AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_BACKEND=openai ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_THINK=1 AG_UI_TUI_BACKEND=openai ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_BACKEND=llama-cpp LLAMA_MODEL_PATH=/path/to.gguf ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_APPROVE=1 AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;
;;;; TUI stderr → ./ag-ui-tui.error.log (override: AG_UI_TUI_ERROR_LOG).
;;;;
;;;; Deps from ghcr.io/egao1980/cl-systems (tuition:2.3.0). First-party
;;;; siblings override OCI when present. Dummy `lm-studio` token is unset.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&DEMO FAIL: ~A~%" c)
        (uiop:print-backtrace :condition c :stream *error-output*)
        (uiop:quit 1)))

(load (merge-pathnames "bootstrap.lisp"
                       (uiop:pathname-directory-pathname
                        (or *load-truename* *compile-file-truename*
                            (merge-pathnames "scripts/" (uiop:getcwd))))))

(defun %unquote-dotenv (s)
  (let ((n (length s)))
    (if (and (>= n 2)
             (or (and (char= (char s 0) #\") (char= (char s (1- n)) #\"))
                 (and (char= (char s 0) #\') (char= (char s (1- n)) #\'))))
        (subseq s 1 (1- n))
        s)))

(defun %dummy-lmstudio-token-p (value)
  (and value
       (plusp (length value))
       (member (string-trim '(#\Space #\Tab) value)
               '("lm-studio" "lmstudio")
               :test #'string-equal)))

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
                (when (and (plusp (length k))
                           (let ((cur (uiop:getenv k)))
                             (or (null cur) (zerop (length cur))
                                 (%dummy-lmstudio-token-p cur))))
                  (setf (uiop:getenv k) v))))))))))

(defun %scrub-dummy-lmstudio-tokens ()
  (dolist (k '("OPENAI_API_KEY" "LM_API_TOKEN"))
    (when (%dummy-lmstudio-token-p (uiop:getenv k))
      (setf (uiop:getenv k) ""))))

(when *workspace-root*
  (%apply-dotenv-file (merge-pathnames ".env" *workspace-root*)))
(%apply-dotenv-file (merge-pathnames ".env" *tui-root*))
(%scrub-dummy-lmstudio-tokens)

(unless (asdf:find-system "tuition" nil)
  (error "tuition not installed — run ./scripts/setup-client.sh && ros -l scripts/install.lisp"))

(asdf:load-system "ag-ui-backend-tui/demo")
(ag-ui-backend-tui/demo:main)
(uiop:quit 0)
