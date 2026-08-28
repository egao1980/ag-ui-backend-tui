;;;; AG-UI TUI demo: async agent → encoder → transcript / tuition.
;;;;
;;;;   AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_VERBOSE=1 AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;   AG_UI_TUI_PROMPT='hello' AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
;;;;
;;;; Interactive (tty):  ros -l scripts/demo.lisp
;;;; Live LM Studio:     AG_UI_TUI_BACKEND=openai ros -l scripts/demo.lisp
;;;;
;;;; Tuition is not on OCI yet. Clone atgreen/cl-tuition v2.3.0 and either
;;;; put it on CL_SOURCE_REGISTRY or set TUITION_PATH.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&DEMO FAIL: ~A~%" c)
        (uiop:print-backtrace :condition c :stream *error-output*)
        (uiop:quit 1)))

(defun %register-tuition ()
  (when (asdf:find-system "tuition" nil)
    (return-from %register-tuition t))
  (dolist (dir (list (uiop:getenv "TUITION_PATH")
                     (namestring
                      (merge-pathnames
                       "cl-tuition/"
                       (uiop:pathname-parent-directory-pathname
                        (or *load-truename* *default-pathname-defaults*))))
                     "/tmp/cl-tuition/"))
    (when dir
      (let ((asd (probe-file (merge-pathnames "tuition.asd"
                                              (uiop:ensure-directory-pathname dir)))))
        (when asd
          (asdf:load-asd asd)
          (return t))))))

(ql:quickload '("trivial-channels" "version-string" "serapeum" "cl-base64")
              :silent t)
(%register-tuition)
(asdf:load-system "ag-ui-backend-tui/demo")

(ag-ui-backend-tui/demo:main)
(uiop:quit 0)
