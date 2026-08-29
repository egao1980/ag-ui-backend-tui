(in-package #:ag-ui-backend-tui)

(defvar *tui-error-log-stream* nil)
(defvar *tui-error-log-path* nil
  "Pathname of the active TUI error log, or NIL.")

(defun tui-error-log-path ()
  "Default: cwd `ag-ui-tui.error.log`. Override with AG_UI_TUI_ERROR_LOG."
  (or (let ((v (uiop:getenv "AG_UI_TUI_ERROR_LOG")))
        (when (and v (plusp (length v)))
          (uiop:ensure-absolute-pathname
           (uiop:parse-native-namestring v)
           (uiop:getcwd))))
      (merge-pathnames "ag-ui-tui.error.log" (uiop:getcwd))))

(defun %open-tui-error-log (path)
  (ensure-directories-exist path)
  (open path :direction :output :if-exists :append :if-does-not-exist :create
             :external-format :utf-8))

(defun call-with-tui-error-log (path fn)
  "Bind *ERROR-OUTPUT* / *TRACE-OUTPUT* to a file (append). Reuses an open log.
   WARN/trace stay on disk — they do not paint over the tuition alt-screen."
  (if *tui-error-log-stream*
      (let ((*error-output* *tui-error-log-stream*)
            (*trace-output* *tui-error-log-stream*))
        (funcall fn))
      (let* ((p (pathname (or path (tui-error-log-path))))
             (tty *error-output*)
             (stream (%open-tui-error-log p)))
        (unwind-protect
             (progn
               (format tty "~&; tui error log: ~a~%" p)
               (force-output tty)
               (format stream "~&;; ag-ui-tui error log opened~%")
               (finish-output stream)
               (let ((*tui-error-log-stream* stream)
                     (*tui-error-log-path* p)
                     (*error-output* stream)
                     (*trace-output* stream))
                 (funcall fn)))
          (close stream :abort nil)))))

(defmacro with-tui-error-log ((&optional path) &body body)
  `(call-with-tui-error-log ,path (lambda () ,@body)))

(defun ensure-http-encodings ()
  "Load optional br/zstd backends so Accept-Encoding does not WARN mid-request."
  (dolist (sys '("http-encoding-brotli" "http-encoding-zstd"))
    (ignore-errors (asdf:load-system sys :verbose nil)))
  nil)

(defmacro with-tui-runtime (&body body)
  "Bind libuv + async HTTP. Same shape as cl-stack-llm-tui WITH-RUNTIME.
   Tuition (if loaded) stays on the caller thread; never http:request here."
  `(progn
     (setf http-backend-async:*event-backend-maker*
           #'event-backend-libuv:make-libuv-backend)
     (let* ((eb (event-backend-libuv:make-libuv-backend))
            (el (event:make-event-loop eb)))
       (event:with-event-backend (eb)
         (event:with-event-loop-var (el)
           (let ((http:*http-backend* (http-backend-async:make-async-backend)))
             (ensure-http-encodings)
             ,@body))))))
