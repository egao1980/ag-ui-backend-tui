(in-package #:ag-ui-backend-tui)

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
             ,@body))))))
