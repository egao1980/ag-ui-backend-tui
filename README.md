# ag-ui-backend-tui

AG-UI **sink**: fold typed events into a transcript. Paint is optional.

Consumes **AG-UI events only** — never `ai-agent-protocol` `:part` / `agent-run`.
No `tui-protocol`. Tuition is a paint backend (`ag-ui-backend-tui/tuition`), not the reducer.

```lisp
(asdf:load-system "ag-ui-backend-tui")

(let ((tr (ag-ui-backend-tui:make-transcript)))
  (ag-ui-backend-tui:apply-ag-ui-event
   tr (ag-ui-protocol:make-text-message-content-event :message-id "m" :delta "hi"))
  (ag-ui-backend-tui:render-transcript tr))
;; ⇒ "status=idle
;; desk> hi
;; "
```

Loop ownership when painting: tuition `tui:run` on the main thread; `event-protocol:run` (libuv) on a side thread; hop events with `tui:send` of `ag-ui-event-msg`. Never `http:request` on the tuition thread. `with-tui-runtime` binds libuv + `http-backend-async`.

`STATE_DELTA` / snapshots are wave-1 no-ops.

Tracks [cl-stack#187](https://github.com/egao1980/cl-stack/issues/187).

## License

MIT
