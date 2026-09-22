# Task 4: Phase constants and error strings (TDD)

**Files:**
- Create: `rime/lua/ime_translate/state.lua`
- Test: `tests/test_state.lua`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `state.IDLE` / `state.RESULT` / `state.ERROR` — the string constants
    `"idle"` / `"result"` / `"error"`
  - `state.BUSY` — the constant `"busy"`, **unreachable in v1** (librime is
    single-threaded while blocking synchronously and receives no keys); kept
    only for a future async route
  - `state.error_message(code) -> "✗ …"` — the eight error strings, with
    unknown codes falling back to `"✗ 翻译失败"`

> **This module holds no state object.** An FSM constructor like `state.new()`
> becomes a module singleton, and librime-lua gives every registered component
> one shared Lua state — phase and translation would be shared across input
> sessions (design §6.1). Session state belongs entirely to Task 7's
> `session.lua`, in `Context` properties. The `eq(state.new, nil, ...)` below is
> the negative assertion guarding that.

> The `✗ …` strings stay Chinese: they are shown in the candidate window of a
> Chinese IME to a Chinese-reading user. They are UI copy, not project prose.

- [ ] **Step 1: Write the failing test**

`tests/test_state.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local state = require("ime_translate.state")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

eq(state.IDLE, "idle", "IDLE")
eq(state.RESULT, "result", "RESULT")
eq(state.ERROR, "error", "ERROR")
eq(state.BUSY, "busy", "BUSY constant kept but unreachable in v1")

eq(state.error_message("conn_refused"), "✗ 翻译服务未启动", "conn")
eq(state.error_message("timeout"), "✗ 翻译超时", "timeout")
eq(state.error_message("http_error"), "✗ 翻译失败", "http")
eq(state.error_message("bad_json"), "✗ 翻译失败", "json")
eq(state.error_message("empty"), "✗ 翻译失败", "empty")
eq(state.error_message("too_long"), "✗ 文本过长", "too long")
eq(state.error_message("auth_error"), "✗ 密钥无效", "auth")
eq(state.error_message("rate_limited"), "✗ 请求过频", "rate limit")
eq(state.error_message("who_knows"), "✗ 翻译失败", "unknown code fallback")
eq(state.error_message(nil), "✗ 翻译失败", "nil code fallback")

-- The module must export no mutable state
eq(state.new, nil, "no FSM constructor")
eq(state.phase, nil, "no module-level phase")
print(("test_state: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_state.lua`
Expected: FAIL (`module 'ime_translate.state' not found`)

- [ ] **Step 3: Implement**

`rime/lua/ime_translate/state.lua`:

```lua
-- Phase constants and error strings. Stateless -- session state is session.lua.
local M = {}

M.IDLE, M.RESULT, M.ERROR = "idle", "result", "error"
-- Unreachable in v1: while blocking synchronously librime is single-threaded
-- and receives no keys at all, so busy can never be observed. The constant is
-- kept only so the semantics come back if an async route is taken later.
M.BUSY = "busy"

local messages = {
  conn_refused = "✗ 翻译服务未启动",
  timeout      = "✗ 翻译超时",
  http_error   = "✗ 翻译失败",
  bad_json     = "✗ 翻译失败",
  empty        = "✗ 翻译失败",
  too_long     = "✗ 文本过长",
  -- Cloud only. These two are separate codes because the user's action differs
  -- completely (fix the key vs wait); sharing "translation failed" would be the
  -- same as showing nothing.
  auth_error   = "✗ 密钥无效",
  rate_limited = "✗ 请求过频",
}

function M.error_message(code) return messages[code] or "✗ 翻译失败" end

return M
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_state.lua`
Expected: `test_state: 16 assertions OK`

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/state.lua tests/test_state.lua
git commit -m "feat: phase constants and error strings, stateless module"
```
