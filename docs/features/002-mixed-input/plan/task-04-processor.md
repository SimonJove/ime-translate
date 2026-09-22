# Task 4: The processor locks and switches (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/session.lua` (two accessors)
- Modify: `rime/lua/ime_translate_processor.lua` (the tap path; the `decide`
  call)
- Test: `tests/test_session.lua`, `tests/test_processor.lua` (append before
  each final `print`; the processor's fake context gains three members)

**Interfaces:**
- Consumes:
  - `shift_tap.observe(down, key, now) -> down', tapped` (Task 1)
  - `decide.decide(key, phase, draft_empty, draft_ascii)` (Task 2)
  - librime-lua's `ctx:confirm_current_selection()`,
    `ctx:get_option(name)` and `ctx:set_option(name, bool)`
  - librime-lua's global `rime_api.get_time_ms()` (upstream F22), when it
    exists
- Produces:
  - `session.shift_down(ctx) -> { code, at } or nil`, shift_tap's `down`
  - `session.set_shift_down(ctx, down or nil)`
  - Stored in the Context property `ime_translate.shift_down` as
    `"keycode@ms"`: `"keycode@"` with no clock, `""` when none.
  - The processor's Shift-tap path, which Task 5 wires and Task 6 observes.

Design §5.5. On a lone Shift tap:
- With a draft open, the processor confirms the current selection, which locks
  the segment, and only then switches `ascii_mode`. The spike found that the
  order matters: switching first re-reads the open segment, `readme` turning
  into `热爱多么`. The source says why: `set_option` recomposes everything not
  yet confirmed (upstream F20).
- With no draft, it only switches.

In both cases the tap returns `kAccepted`. The Shift press itself is passed on,
as before.

Three rules sit around the tap:
- **Every key goes past the watcher first,** ahead of check 2 and its early
  return, so any key between the press and the release is seen.
- **The Shift state is kept apart from `session.clear()`.** A Shift press in
  the result phase voids the translation through the catch-all, and the tap
  still has to count.
- **The caret rule is Enter's.** With the caret inside the input, the first tap
  only moves it to the end.
- **The clock is librime-lua's** `rime_api.get_time_ms()`, read once per key.
  Where it is missing, the processor passes no clock and any hold counts. The
  headless tests have no `rime_api` until they install a fake one.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_session.lua`, just before its final `print(...)`:

```lua
---------- feature 002 (design §5.5): the Shift state ----------
local s = fake_ctx("今天")
eq(session.shift_down(s), nil, "no Shift pending at first")
session.set_shift_down(s, { code = 0xFFE1, at = 123456 })
local d = session.shift_down(s)
eq(d and d.code, 0xFFE1, "a pending Shift reads back its keycode")
eq(d and d.at, 123456, "and the time it went down")
eq(s.props["ime_translate.shift_down"], "65505@123456", "stored as keycode@ms")
session.clear(s)
d = session.shift_down(s)
eq(d and d.code, 0xFFE1, "clear() leaves it: the press that voids a translation still taps")
session.set_shift_down(s, { code = 0xFFE2 })
d = session.shift_down(s)
eq(d and d.code, 0xFFE2, "with no clock the keycode is kept")
eq(d and d.at, nil, "and the time is nil")
eq(s.props["ime_translate.shift_down"], "65506@", "stored as keycode@")
session.set_shift_down(s, nil)
eq(session.shift_down(s), nil, "and it can be dropped")
eq(s.props["ime_translate.shift_down"], "", "an empty string when none")
eq(session.shift_down(nilctx), nil, "a store that returns nil reads as none")
```

In `tests/test_processor.lua`, the fake context gains the option store and the
lock. Each call is recorded in `trace`, so a test can check the order. In
`fake()`, after the `get_commit_text = …` line, add:

```lua
    opts = {}, trace = {},
    get_option = function(self, name) return self.opts[name] == true end,
    set_option = function(self, name, v)
      self.opts[name] = v
      self.trace[#self.trace + 1] = name .. "=" .. tostring(v)
    end,
    confirm_current_selection = function(self)
      self.trace[#self.trace + 1] = "confirm"
      return true
    end,
```

Then append, just before its final `print(...)`:

```lua
---------- feature 002 (design §5.5): the Shift tap ----------
local SHIFT_L, SHIFT_R, CTRL, REL = 0xFFE1, 0xFFE2, 0x4, 1 << 30
local function trace(c) return table.concat(c.trace, ",") end
-- librime-lua's clock (upstream F22), faked: every read is 10 ms after the one
-- before, and a test can jump it
local clock = 0
rime_api = { get_time_ms = function() clock = clock + 10; return clock end }
-- A lone tap in Squirrel's form (upstream F21): the press carries the Shift
-- bit, the release only the release bit.
local function tap(env, code)
  local a = processor(key(code or SHIFT_L, SHIFT), env)
  return a, processor(key(code or SHIFT_L, REL, true), env)
end

-- a tap with a draft open: lock first, then switch; nothing committed
env, ctx, seg = fake("今天", "jintian")
calls = {}
local a, b = tap(env)
eq(a, kNoop, "the Shift press passes on")
eq(b, kAccepted, "the release of a lone tap is taken")
eq(trace(ctx), "confirm,ascii_mode=true", "the segment is locked, then the mode is English")
eq(#env.committed, 0, "a tap commits nothing")
eq(ctx._text, "今天", "a tap keeps the draft")
eq(ctx.input, "jintian", "and the input")
eq(#calls, 0, "a tap never translates")
-- tapping back locks the English and returns to Chinese
ctx._text, ctx.input, ctx.caret_pos = "今天readme", "jintianreadme", 13
tap(env)
eq(trace(ctx), "confirm,ascii_mode=true,confirm,ascii_mode=false", "tapping back locks the English, then Chinese")

-- no draft: switch only, there is nothing to lock
env, ctx, seg = fake("")
a, b = tap(env)
eq(b, kAccepted, "a tap with no draft is taken")
eq(trace(ctx), "ascii_mode=true", "no draft: switch only")

-- right Shift, and a release that still carries the Shift bit, tap the same
env, ctx, seg = fake("今天", "jintian")
processor(key(SHIFT_R, SHIFT), env)
eq(processor(key(SHIFT_R, SHIFT | REL, true), env), kAccepted, "right Shift taps")
eq(trace(ctx), "confirm,ascii_mode=true", "and locks, then switches")

-- Shift+Enter is not a tap: the draft commits and the mode stays (the Shift
-- release that switched to English in feature 001, Task 10)
env, ctx, seg = fake("今天", "jintian")
processor(key(SHIFT_L, SHIFT), env)
eq(press(env, RET, SHIFT), kAccepted, "shift-enter is taken")
eq(env.committed[1], "今天", "and commits the draft")
eq(processor(key(SHIFT_L, REL, true), env), kNoop, "the Shift release after it passes on")
eq(trace(ctx), "", "shift-enter locks and switches nothing")

-- Shift+letter, a capital, is not a tap
env, ctx, seg = fake("今天", "jintian")
processor(key(SHIFT_L, SHIFT), env)
press(env, string.byte("A"), SHIFT)
processor(key(string.byte("A"), SHIFT | REL, true), env)
eq(processor(key(SHIFT_L, REL, true), env), kNoop, "the release after a capital passes on")
eq(trace(ctx), "", "a capital switches nothing")

-- Control+Shift, the schema-switch chord, is not a tap
env, ctx, seg = fake("今天", "jintian")
processor(key(SHIFT_L, SHIFT | CTRL), env)
eq(processor(key(SHIFT_L, CTRL | REL, true), env), kNoop, "control-shift passes on")
eq(trace(ctx), "", "control-shift switches nothing")

-- the caret inside the input: the first tap only moves it, as Enter does
env, ctx, seg = fake("今天天气很", "jintiantianqihenhao")
ctx.caret_pos = 5
a, b = tap(env)
eq(b, kAccepted, "a tap with the caret inside is taken")
eq(ctx.caret_pos, #ctx.input, "the caret moved to the end")
eq(trace(ctx), "", "and nothing is locked or switched yet")
tap(env)
eq(trace(ctx), "confirm,ascii_mode=true", "the next tap locks and switches")

-- a tap in the result phase: the press voids the translation, the tap counts
env, ctx, seg = fake("今天有点累")
answer, calls = { true, "Tired" }, {}
press(env, RET)
tap(env)
eq(seg.prompt, "", "the Shift press dropped the translation")
eq(trace(ctx), "confirm,ascii_mode=true", "and the tap locks and switches")
eq(#env.committed, 0, "nothing committed")
press(env, RET)
eq(#calls, 2, "enter then translates again, never commits the voided one")

-- Shift held past 500 ms is a held Shift, not a tap (ascii_composer's rule,
-- upstream F18)
env, ctx, seg = fake("今天", "jintian")
processor(key(SHIFT_L, SHIFT), env)
clock = clock + 600
eq(processor(key(SHIFT_L, REL, true), env), kNoop, "a Shift held 600 ms passes on")
eq(trace(ctx), "", "a long hold switches nothing")

-- the Shift state is per input box (design §6.1): a press in one box and a
-- release in another is no tap
local env1 = fake("今天", "jintian")
local env2, ctx2 = fake("好的", "haode")
processor(key(SHIFT_L, SHIFT), env1)
eq(processor(key(SHIFT_L, REL, true), env2), kNoop, "a release in another box is not a tap")
eq(trace(ctx2), "", "the other box switches nothing")

-- a librime-lua with no get_time_ms: no clock, and a tap still counts
rime_api = nil
env, ctx, seg = fake("今天", "jintian")
tap(env)
eq(trace(ctx), "confirm,ascii_mode=true", "with no clock a tap still locks and switches")

-- a draft with no Chinese: Enter commits it as is (Task 2's rule, wired)
env, ctx, seg = fake("git status", "git status")
calls = {}
eq(press(env, RET), kAccepted, "enter on an English-only draft is taken")
eq(env.committed[1], "git status", "and commits it as is")
eq(#calls, 0, "with no backend call")
-- a mixed draft is translated whole, the English inside it included
env, ctx, seg = fake("用git提交README文件", "yonggittijiaoREADMEwenjian")
answer, calls = { true, "Use git to submit the README file" }, {}
press(env, RET)
eq(calls[1], "用git提交README文件", "a mixed draft goes to the backend whole")
eq(seg.prompt, "  -> Use git to submit the README file", "and its translation is shown")
eq(#env.committed, 0, "and nothing is committed yet")
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `lua tests/test_session.lua; lua tests/test_processor.lua`
Expected: both FAIL.
- `test_session` fails with `attempt to call a nil value (field 'shift_down')`.
- `test_processor` fails at its first new assertion:
  `the release of a lone tap is taken: got "2" want "1"`.

- [ ] **Step 3: Implement the session accessors**

In `rime/lua/ime_translate/session.lua`, add the key after `K_DRAFT`:

```lua
local K_SHIFT = "ime_translate.shift_down"
```

and, after `M.snapshot`, the two accessors:

```lua
-- Feature 002 (design §5.5): shift_tap's `down`, a Shift pressed alone and not
-- yet released -- its keycode and the time it went down. Kept apart from
-- clear(): a Shift press in the result phase voids the translation, and its
-- tap must still count. Stored as "keycode@ms", "keycode@" with no clock.
function M.shift_down(ctx)
  local code, at = (ctx:get_property(K_SHIFT) or ""):match("^(%d+)@(%d*)$")
  if not code then return nil end
  return { code = tonumber(code), at = tonumber(at) }
end
function M.set_shift_down(ctx, down)
  ctx:set_property(K_SHIFT, down and (down.code .. "@" .. (down.at or "")) or "")
end
```

- [ ] **Step 4: Implement the tap path in the processor**

In `rime/lua/ime_translate_processor.lua`, require the module after `decide`:

```lua
local shift_tap = require("ime_translate.shift_tap")
```

Move the construction of `k` up, from just before the `decide` call to just
after `local draft = session.draft(ctx)`. Then feed every key to the watcher
there, before check 2:

```lua
  local draft = session.draft(ctx)

  -- modifier goes in raw: decide drops Lock and every bit it does not read
  -- (R15, Task 8). release is a method on the KeyEvent, not a field.
  local k = { keycode = key.keycode, modifier = key.modifier, release = key:release() }

  -- Feature 002 (design §5.5): every key goes past the Shift-tap watcher
  -- before any early return, so a key between a Shift press and its release
  -- is always seen and makes the Shift a modifier. The clock is librime-lua's
  -- (upstream F22); without one, observe drops the 500 ms limit. The state is
  -- written only when there is some, not on every letter.
  local now = rime_api and rime_api.get_time_ms and rime_api.get_time_ms()
  local down_before = session.shift_down(ctx)
  local down, tapped = shift_tap.observe(down_before, k, now)
  if down or down_before then session.set_shift_down(ctx, down) end
```

After check 2, and before the `decide` call, add the tap path:

```lua
  -- A lone Shift tap switches Chinese and English (design §5.5). With a draft
  -- open, the current segment is locked first: confirmed, its conversion or
  -- its letters stay as they are, where switching first would re-read them as
  -- the other mode (the spike, decisions.md). It commits nothing and clears
  -- nothing. With the caret inside the input the composition stops at the
  -- caret (F15), so, as for Enter, the first tap only moves it to the end.
  if tapped then
    if ctx.input ~= "" then
      if caret_inside(ctx) then
        ctx.caret_pos = #ctx.input
        return kAccepted
      end
      ctx:confirm_current_selection()
    end
    local ascii = not ctx:get_option("ascii_mode")
    ctx:set_option("ascii_mode", ascii)
    log(S, "shift tap: " .. (ascii and "english" or "chinese"))
    return kAccepted
  end
```

and pass the new argument to `decide`. A draft with no byte ≥ 0x80 has no
Chinese and no full-width mark:

```lua
  local action = decide.decide(k, session.phase(ctx), ctx.input == "",
                               not draft:find("[\128-\255]"))
```

- [ ] **Step 5: Run them and confirm they pass**

Run: `lua tests/test_session.lua && lua tests/test_processor.lua && scripts/run_tests.sh`
Expected: `test_session: 47 assertions OK`,
`test_processor: 120 assertions OK`, and every file PASS.

- [ ] **Step 6: Commit**

```bash
git add rime/lua/ime_translate/session.lua rime/lua/ime_translate_processor.lua \
        tests/test_session.lua tests/test_processor.lua
git commit -m "feat: a Shift tap locks the segment, then switches the mode"
```
