# Task 7: Session state and draft snapshot (TDD)

**Files:**
- Create: `rime/lua/ime_translate/session.lua`
- Test: `tests/test_session.lua`

**Interfaces:**
- Consumes: `state.IDLE/RESULT/ERROR` and `state.error_message` (Task 4)
- Produces:
  - `session.draft(ctx) -> string` — the full current Chinese draft
    (`ctx:get_commit_text()`, which under `fluid_editor` is the whole sentence)
  - `session.phase(ctx)`, `session.text(ctx)`, `session.code(ctx)`,
    `session.snapshot(ctx)` — all returning strings
  - `session.set_result(ctx, draft, text)`, `session.set_error(ctx, draft, code)`,
    `session.clear(ctx)`
  - `session.stale(ctx) -> bool` — current draft ≠ snapshot, i.e. the
    translation has expired
  - `session.prompt(ctx) -> string` — what the processor writes into the last
    segment's `prompt` for the current phase (design §6.4, decision D1):
    `"  -> "` plus the translation, two spaces plus the `✗` reason, or empty

> **Why state must live on `Context`**: librime-lua gives every registered Lua
> component **one** shared Lua state at init, so a `require`d module's upvalues
> are process-wide and would leak translations between applications and input
> boxes. `Context` is per session, and the processor reaches it through
> `env.engine.context`.
>
> **If spike S4 found `ctx:set_property/get_property` unavailable**, change this
> module's four getters/setters to read and write a module-level table
> `store[tostring(env.engine)]`, and delete the key in each component's `fini`.
> The interface signatures stay identical, so Task 9 is unaffected.
>
> **Decision D1 (2026-09-21)** settled the display: the translation is shown
> through `segment.prompt`, which `get_commit_text()` never reads, so the draft
> is a clean version. Spike S11 measured the candidate display breaking exactly
> this module's snapshot comparison, and the prompt keeping it intact.

- [ ] **Step 1: Write the failing test**

`tests/test_session.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local session = require("ime_translate.session")
local state = require("ime_translate.state")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

-- A fake Context: a property table plus a mutable commit text
local function fake_ctx(text)
  local props = {}
  return {
    _text = text or "",
    props = props,
    get_property = function(self, k) return props[k] end,
    set_property = function(self, k, v) props[k] = v end,
    get_commit_text = function(self) return self._text end,
  }
end

-- initial state
local c = fake_ctx("今天有点累")
eq(session.phase(c), state.IDLE, "fresh ctx is idle")
eq(session.text(c), "", "fresh text empty")
eq(session.code(c), "", "fresh code empty")
eq(session.snapshot(c), "", "fresh snapshot empty")
eq(session.draft(c), "今天有点累", "draft from get_commit_text")
eq(session.stale(c), false, "idle is never stale")
eq(session.prompt(c), "", "idle shows nothing")

-- set_result
session.set_result(c, "今天有点累", "A bit tired today")
eq(session.phase(c), state.RESULT, "phase result")
eq(session.text(c), "A bit tired today", "translation stored")
eq(session.code(c), "", "code cleared on result")
eq(session.snapshot(c), "今天有点累", "snapshot stored")
eq(session.stale(c), false, "not stale right after set_result")
eq(session.prompt(c), "  -> A bit tired today", "result prompt: the measured S11 form")

-- the draft changed -> expired
c._text = "今天有点累了"
eq(session.stale(c), true, "draft changed -> stale")
c._text = "今天有点累"
eq(session.stale(c), false, "draft restored -> not stale")

-- clear
session.clear(c)
eq(session.phase(c), state.IDLE, "cleared to idle")
eq(session.text(c), "", "text cleared")
eq(session.snapshot(c), "", "snapshot cleared")
eq(session.stale(c), false, "idle not stale even with text present")
eq(session.prompt(c), "", "cleared prompt is empty")

-- set_error
session.set_error(c, "今天有点累", "timeout")
eq(session.phase(c), state.ERROR, "phase error")
eq(session.code(c), "timeout", "code stored")
eq(session.text(c), "", "text cleared on error")
eq(session.stale(c), false, "error not stale initially")
eq(session.prompt(c), "  ✗ 翻译超时", "error prompt carries the reason")
c._text = "今天"
eq(session.stale(c), true, "error goes stale on edit too")

-- a phase with no snapshot is stale: nothing ties it to this draft
local m = fake_ctx("今天")
m.props["ime_translate.phase"] = state.RESULT
eq(session.stale(m), true, "result without a snapshot is stale")

-- two contexts do not affect each other (exactly what a module singleton cannot do)
local a, b = fake_ctx("甲"), fake_ctx("乙")
session.set_result(a, "甲", "AAA")
eq(session.phase(b), state.IDLE, "ctx b unaffected by ctx a")
eq(session.text(b), "", "ctx b has no translation")
eq(session.text(a), "AAA", "ctx a keeps its own")

-- empty draft
local e = fake_ctx("")
eq(session.draft(e), "", "empty draft")
-- must also be safe when get_commit_text returns nil
e.get_commit_text = function() return nil end
eq(session.draft(e), "", "nil commit text -> empty string")
print(("test_session: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_session.lua`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement**

`rime/lua/ime_translate/session.lua`:

```lua
-- Session state, all stored in librime Context properties, isolated per
-- session. Do not put any of this in module upvalues: librime-lua gives every
-- component one shared Lua state, so module-level state leaks translations
-- between applications and input boxes.
local state = require("ime_translate.state")
local M = {}

local K_PHASE = "ime_translate.phase"
local K_TEXT  = "ime_translate.text"
local K_CODE  = "ime_translate.code"
local K_DRAFT = "ime_translate.draft"

-- Under fluid_editor the composition does not auto-commit, so
-- get_commit_text() returns the whole Chinese draft, confirmed segments
-- included.
function M.draft(ctx) return ctx:get_commit_text() or "" end

function M.phase(ctx)
  local p = ctx:get_property(K_PHASE)
  if p == nil or p == "" then return state.IDLE end
  return p
end

function M.text(ctx)     return ctx:get_property(K_TEXT)  or "" end
function M.code(ctx)     return ctx:get_property(K_CODE)  or "" end
function M.snapshot(ctx) return ctx:get_property(K_DRAFT) or "" end

function M.set_result(ctx, draft, text)
  ctx:set_property(K_DRAFT, draft)
  ctx:set_property(K_TEXT, text)
  ctx:set_property(K_CODE, "")
  ctx:set_property(K_PHASE, state.RESULT)
end

function M.set_error(ctx, draft, code)
  ctx:set_property(K_DRAFT, draft)
  ctx:set_property(K_TEXT, "")
  ctx:set_property(K_CODE, code)
  ctx:set_property(K_PHASE, state.ERROR)
end

function M.clear(ctx)
  ctx:set_property(K_PHASE, state.IDLE)
  ctx:set_property(K_TEXT, "")
  ctx:set_property(K_CODE, "")
  ctx:set_property(K_DRAFT, "")
end

-- Has the translation expired? The draft text is its own version identifier;
-- there is no separate counter. That holds only because the display stays out
-- of get_commit_text() (design §6.1, decision D1).
function M.stale(ctx)
  if M.phase(ctx) == state.IDLE then return false end
  return M.draft(ctx) ~= M.snapshot(ctx)
end

-- The display (design §6.4): what the processor writes into the last
-- segment's prompt. "  -> " is the form spike S11 measured in the preedit.
function M.prompt(ctx)
  local p = M.phase(ctx)
  if p == state.RESULT then return "  -> " .. M.text(ctx) end
  if p == state.ERROR then return "  " .. state.error_message(M.code(ctx)) end
  return ""
end

return M
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_session.lua`
Expected: `test_session: 32 assertions OK`

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/session.lua tests/test_session.lua
git commit -m "feat: session state in Context properties with draft snapshots"
```
