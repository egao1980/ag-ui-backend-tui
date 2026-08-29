# ag-ui-backend-tui

AG-UI **sink**: fold typed events into a transcript. Paint is optional.

Consumes **AG-UI events only** — never `ai-agent-protocol` `:part` / `agent-run`.
No `tui-protocol`. Tuition is a paint backend (`ag-ui-backend-tui/tuition`), not the reducer.

Reusable as a **client-side sink + history**, not a wire client: no `run-agent`, no HTTP/SSE transport. Fold events into a `transcript`, paint with `/tuition`, resubmit with `transcript-ag-ui-messages` / `make-run-agent-input-from-transcript` (messages + shared state). The demo (`ag-ui-backend-tui/demo`) is product glue (agent + encoder), not the library.

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

Protocol fold (`STATE_SNAPSHOT` / `STATE_DELTA`, interrupts, activity) lives in `ag-ui-client`. The transcript keeps a display view and delegates the document to that reducer.

Loop ownership when painting: tuition `tui:run` on the main thread; `event-protocol:run` (libuv) on a side thread; hop events with `tui:send` of `ag-ui-event-msg`. Never `http:request` on the tuition thread. `with-tui-runtime` binds libuv + `http-backend-async`.

## Demo

`ag-ui-backend-tui/demo` wires `ai-agent-protocol` → `/ag-ui` encoder → this sink.

Backends (`AG_UI_TUI_BACKEND`):

| value | LLM |
|---|---|
| `mock` (default) | in-process scripted calculator + reasoning |
| `openai` / `lmstudio` | `llm-protocol-openai` (tools) |
| `llama-cpp` / `llama` | native [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) — generate only, no tools |

`llama-cpp` is loaded on demand (not a demo ASDF dep). Needs a chat GGUF (`LLAMA_MODEL_PATH` / `LLAMA_CPP_MODEL`, else first non-embed file under `~/.lmstudio/models`). Overlay: local `llama-cpp` build or OCI native. Skip embedding GGUFs.

HITL: `AG_UI_TUI_APPROVE=1` gates `add`. Line mode auto-resumes unless `AG_UI_TUI_AUTO_APPROVE=0`. Interactive TUI: `y`/`n` (or `yes`/`no`) answers the open interrupt — new user text is blocked until then.

Deps from `ghcr.io/egao1980/cl-systems` via `cl-repository-client`. First-party siblings override OCI when present (in-progress checkouts). No workspace `:tree`. Loads `../.env` when present.

```bash
./scripts/setup-client.sh          # client → ./.cl-repository
ros -l scripts/install.lisp        # latest GHCR pins (tuition:2.3.0, …)

# line mode (no tty / pipes) — mock agent, reasoning + tool + text deltas
AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp

# drip each event
AG_UI_TUI_VERBOSE=1 AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp

# interactive tuition TUI (needs a tty + atgreen/cl-tuition v2.3.0)
# WARN/trace → ./ag-ui-tui.error.log (or AG_UI_TUI_ERROR_LOG)
ros -l scripts/demo.lisp

# live LM Studio (tools)
AG_UI_TUI_BACKEND=openai ros -l scripts/demo.lisp

# native llama.cpp (chat GGUF, no tools)
AG_UI_TUI_BACKEND=llama-cpp LLAMA_MODEL_PATH=/path/to/model.gguf \
  AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp

# HITL: pause on add, auto-resume in line mode
AG_UI_TUI_APPROVE=1 AG_UI_TUI_LINE=1 ros -l scripts/demo.lisp
```

Mock: two numbers in the prompt → `add` tool (after a reasoning line); otherwise echo. Default prompt is `What is 17 plus 25?` (or `Say hello in five words.` on llama.cpp).

Tuition is `ghcr.io/egao1980/cl-systems/tuition:2.3.0` (plus `version-string`, `trivial-channels`, `serapeum`). Dummy LM Studio token `lm-studio` is treated as unset.

Tracks [cl-stack#187](https://github.com/egao1980/cl-stack/issues/187).

## License

MIT
