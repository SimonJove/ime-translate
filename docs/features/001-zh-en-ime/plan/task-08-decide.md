# Task 8: Pure-function key decisions (TDD)

**Files:**
- Create: `rime/lua/ime_translate/decide.lua`
- Test: `tests/test_decide.lua`

**Interfaces:**
- Consumes: `state.IDLE/RESULT/ERROR` (Task 4)
- Produces: `decide.decide(key, phase, draft_empty) -> action`, where `key` is a
  plain table `{keycode, modifier, release}`. It **touches no rime global, does
  no IO and mutates no state**. `action.type` ∈ `noop` / `translate` /
  `commit_translation` / `commit_draft` / `clear_display` /
  `invalidate_and_pass`

> There is deliberately **no** `toggle_mode` action: schema switching belongs to
> Rime's native `key_binder`. And there is no "pass through and let the engine
> commit the highlighted candidate" action either: the processor commits with
> `commit_text` itself (design §3.1).

- [ ] **Step 1: Write the failing test**

`tests/test_decide.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local decide = require("ime_translate.decide")
local state = require("ime_translate.state")
local n = 0
local function is(key, phase, empty, want, msg)
  n = n + 1
  local got = decide.decide(key, phase, empty).type
  assert(got == want, ("#%d %s: got %q want %q"):format(n, msg, got, want))
end

local RET, ESC = decide.RETURN, decide.ESC
local function k(code, mod, rel) return { keycode = code, modifier = mod or 0, release = rel or false } end
local A = string.byte("a")          -- an ordinary letter key
local D2 = string.byte("2")         -- digit candidate selection
local BACK = 0xFF08                 -- BackSpace
local LEFT = 0xFF51                 -- Left
local UP = 0xFF52                   -- Up (candidate navigation)

-- a release event is always noop, ahead of everything else
is(k(RET, 0, true), state.RESULT, false, "noop", "release beats everything")
is(k(A, 0, true), state.RESULT, false, "noop", "release letter")

-- empty draft: Enter and Shift+Enter both pass through (native newline etc.)
is(k(RET), state.IDLE, true, "noop", "empty draft + return")
is(k(RET, decide.SHIFT), state.IDLE, true, "noop", "empty draft + shift-return")

-- Enter across the three phases
is(k(RET), state.IDLE, false, "translate", "idle + draft -> translate")
is(k(RET), state.RESULT, false, "commit_translation", "result -> commit translation")
is(k(RET), state.ERROR, false, "commit_draft", "error -> commit chinese draft")

-- Shift+Enter: commit the Chinese draft in all three phases
is(k(RET, decide.SHIFT), state.IDLE, false, "commit_draft", "shift-return idle")
is(k(RET, decide.SHIFT), state.RESULT, false, "commit_draft", "shift-return result")
is(k(RET, decide.SHIFT), state.ERROR, false, "commit_draft", "shift-return error")

-- Enter with other modifiers does not take a commit path
is(k(RET, 0x4), state.RESULT, false, "invalidate_and_pass", "ctrl-return in result")
is(k(RET, 0x4), state.IDLE, false, "noop", "ctrl-return in idle")
is(k(RET, 0x8), state.ERROR, false, "invalidate_and_pass", "alt-return in error")

-- Esc
is(k(ESC), state.RESULT, false, "clear_display", "esc in result")
is(k(ESC), state.ERROR, false, "clear_display", "esc in error")
is(k(ESC), state.IDLE, false, "noop", "esc in idle passes to native")

-- Catch-all: with a translation on screen, any other key voids it then passes
-- through (covers continued typing, backspace, cursor, candidate navigation)
is(k(A), state.RESULT, false, "invalidate_and_pass", "letter in result")
is(k(D2), state.RESULT, false, "invalidate_and_pass", "digit select in result")
is(k(BACK), state.RESULT, false, "invalidate_and_pass", "backspace in result")
is(k(LEFT), state.RESULT, false, "invalidate_and_pass", "cursor move in result")
is(k(UP), state.RESULT, false, "invalidate_and_pass", "candidate nav in result")
is(k(A), state.ERROR, false, "invalidate_and_pass", "letter in error")

-- in idle everything passes through, never disturbing native input
is(k(A), state.IDLE, false, "noop", "letter in idle")
is(k(D2), state.IDLE, true, "noop", "digit in idle")
is(k(BACK), state.IDLE, false, "noop", "backspace in idle")

-- decide must be pure: same input twice gives the same result, and the input
-- table is not mutated
local key = k(RET)
local before = key.modifier
decide.decide(key, state.RESULT, false)
n = n + 1; assert(key.modifier == before, "#" .. n .. " decide must not mutate key")
n = n + 1; assert(decide.decide(key, state.RESULT, false).type
              == decide.decide(key, state.RESULT, false).type, "#" .. n .. " deterministic")
print(("test_decide: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_decide.lua`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement**

`rime/lua/ime_translate/decide.lua`:

```lua
-- Pure-function key decisions: references no rime global, does no IO, mutates
-- no state. The glue layer reads the context, executes the action and writes
-- state. That is what makes every branch unit-testable headless.
local state = require("ime_translate.state")
local M = {}

M.RETURN, M.ESC = 0xFF0D, 0xFF1B
M.SHIFT = 0x1

-- Returns { type = ... }:
--   noop                 leave it to later processors, i.e. native behaviour
--   translate            intercept Enter; the glue takes the draft to the backend
--   commit_translation   engine:commit_text(translation)
--   commit_draft         engine:commit_text(Chinese draft) -- skip or fall back
--   clear_display        discard the translation, back to idle, draft stays
--   invalidate_and_pass  void the translation first, then pass through
function M.decide(key, phase, draft_empty)
  if key.release then return { type = "noop" } end

  if key.keycode == M.RETURN and key.modifier == 0 then
    if draft_empty then return { type = "noop" } end
    if phase == state.RESULT then return { type = "commit_translation" } end
    if phase == state.ERROR then return { type = "commit_draft" } end
    return { type = "translate" }
  end

  -- Escape hatch: do not translate this one, just commit the Chinese
  if key.keycode == M.RETURN and key.modifier == M.SHIFT then
    if draft_empty then return { type = "noop" } end
    return { type = "commit_draft" }
  end

  if key.keycode == M.ESC and phase ~= state.IDLE then
    return { type = "clear_display" }
  end

  -- Catch-all: with a translation on screen, any other key invalidates it
  -- before passing through. Rather than enumerating "which keys change the
  -- draft", this covers typing, backspace, cursor movement and candidate
  -- navigation in one rule.
  if phase ~= state.IDLE then return { type = "invalidate_and_pass" } end
  return { type = "noop" }
end

return M
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `lua tests/test_decide.lua && scripts/run_tests.sh`
Expected: `test_decide: 27 assertions OK`, whole suite PASS

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/decide.lua tests/test_decide.lua
git commit -m "feat: pure-function key decisions with Shift+Enter and catch-all"
```
