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

## Demo

`ag-ui-backend-tui/demo` wires `ai-agent-protocol` → `/ag-ui` encoder → this sink.

Deps from `ghcr.io/egao1980/cl-systems` via `cl-repository-client`. First-party siblings override OCI when present (in-progress checkouts). No workspace `:tree`. Loads `../.env` when present.

```bash
./scripts/setup-client.sh          # client → ./.cl-repository
ros -l scripts/install.lisp        # latest GHCR pins (tuition:2.3.0, …)

# line mode (no tty / pipes) — mock agent, tool + text deltas
AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp

# drip each event
AG_UI_TUI_VERBOSE=1 AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp

# interactive tuition TUI (needs a tty + atgreen/cl-tuition v2.3.0)
ros -l scripts/demo.lisp

# live LM Studio
AG_UI_TUI_BACKEND=openai ros -l scripts/demo.lisp
```

Mock: two numbers in the prompt → `add` tool; otherwise echo. Default prompt is `What is 17 plus 25?`.

Tuition is `ghcr.io/egao1980/cl-systems/tuition:2.3.0` (plus `version-string`, `trivial-channels`, `serapeum`). Dummy LM Studio token `lm-studio` is treated as unset.

`STATE_DELTA` / snapshots are wave-1 no-ops.

Tracks [cl-stack#187](https://github.com/egao1980/cl-stack/issues/187).

## License

MIT
