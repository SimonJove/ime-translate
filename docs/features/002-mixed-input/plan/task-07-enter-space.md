# Task 7: Enter and Space in a draft — the Enter way (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/decide.lua` (a Space constant, two actions,
  a fifth argument)
- Modify: `rime/lua/ime_translate_processor.lua` (read what is unselected; run
  the two actions)
- Test: `tests/test_decide.lua`, `tests/test_processor.lua`

**Interfaces:**
- Consumes:
  - `decide.decide(key, phase, draft_empty, draft_ascii)` (Task 2)
  - the processor's caret rule and `ACTS_ON_DRAFT` (feature 001, Task 9)
  - from librime-lua, used as the spike of 2026-09-22 used them (F27):
    `ctx.composition:toSegmentation()` with `get_confirmed_position()` and
    `add_segment(seg)`; `ctx.composition:empty()` and `:back()`;
    `ctx:clear_non_confirmed_composition()`; `ctx:push_input(s)`;
    `ctx:confirm_current_selection()`; the global `Segment(start, end)` and
    its `_end` and `length` setters
- Produces:
  - `decide.decide(key, phase, draft_empty, draft_ascii, unselected)`.
    `unselected` is true when some of the input is not yet selected, that is
    when the confirmed position is short of the input's end. Omitted, it is
    false, and behaviour is as before.
  - `decide.SPACE = 0x20`
  - two new actions:
    - `lock_literal`: Enter in idle with something unselected
    - `literal_space`: Space, with no modifier, a draft open and nothing
      unselected, in any phase

Design §5.5, "the Enter way", which is the user's decision of 2026-09-22.
- **Enter with unselected pinyin** locks it as the letters typed. The
  processor clears what is not confirmed, puts one bare segment over it, and
  confirms that. A segment with no candidate is confirmed as raw input (F20).
- **Space with nothing unselected** pushes a space and confirms it. Natively
  it would commit the whole draft untranslated (F27). With a translation on
  screen, the translation is voided first.
- **Neither action commits, clears, or touches the mode.** The caret rule
  applies to both: with the caret inside the input, the first press only
  moves the caret to the end.

The mechanism is the spike's, observed by the agent (decisions.md, "Feature 002
redesigned").

- [ ] **Step 1: Write the failing tests**

In `tests/test_decide.lua`, Space with no modifier is now a named row, so the
catch-all sweep leaves it out. Replace `named_row`:

```lua
local function named_row(code, m)
  local mods = m & ~LOCK
  if code == ESC then return true end
  if code == RET or code == KP_ENTER then return mods == 0 or mods == SHIFT end
  if code == 0x20 then return mods == 0 end          -- feature 002: Space
  return false
end
```

The processor passes `unselected` on every key, so the sweep runs with it both
false and true. Replace the sweep's `ascii` loop:

```lua
        for _, ascii in ipairs({ false, true }) do
          for _, unsel in ipairs({ false, true }) do
            for ph, want in pairs(WANT) do
              swept = swept + 1
              local got = decide.decide(sweep, ph, empty, ascii, unsel).type
              if got ~= want and not bad then
                bad = ("%#x mod %#x %s empty=%s ascii=%s unsel=%s: got %s want %s"):format(
                  code, m, ph, empty, ascii, unsel, got, want)
              end
            end
          end
        end
```

and append, just before the final `print(...)`:

```lua
---------- feature 002 (design §5.5): the Enter way ----------
local SPACE = 0x20
eq(decide.SPACE, SPACE, "Space is 0x20")
local function is5(key, phase, empty, ascii, unselected, want, msg)
  n = n + 1
  local got = decide.decide(key, phase, empty, ascii, unselected).type
  assert(got == want, ("#%d %s: got %q want %q"):format(n, msg, got, want))
end
-- Enter with unselected pinyin locks it as the letters typed
is5(k(RET), state.IDLE, false, false, true, "lock_literal", "enter, unselected pinyin: lock as letters")
is5(k(KP_ENTER), state.IDLE, false, false, true, "lock_literal", "keypad enter, unselected pinyin")
is5(k(RET, LOCK), state.IDLE, false, false, true, "lock_literal", "enter+lock, unselected pinyin")
is5(k(RET), state.IDLE, false, true, true, "lock_literal", "unselected letters with no Chinese: lock first")
is5(k(RET), state.IDLE, false, false, false, "translate", "nothing unselected: translate, as before")
is5(k(RET), state.IDLE, false, true, false, "commit_draft", "nothing unselected, no Chinese: commit as is")
is5(k(RET), state.IDLE, true, false, true, "noop", "empty draft stays native")
is5(k(RET), state.RESULT, false, false, true, "commit_translation", "result is unchanged")
is5(k(RET), state.ERROR, false, false, true, "commit_draft", "error is unchanged")
is5(k(RET, SHIFT), state.IDLE, false, false, true, "commit_draft", "shift-enter is unchanged")
is5(k(RET, CTRL), state.IDLE, false, false, true, "noop", "control-enter is native")
-- Space with nothing unselected is a literal space; otherwise native
is5(k(SPACE), state.IDLE, false, false, false, "literal_space", "space, nothing unselected: a literal space")
is5(k(SPACE, LOCK), state.IDLE, false, false, false, "literal_space", "space+lock, nothing unselected")
is5(k(SPACE), state.RESULT, false, false, false, "literal_space", "space in result: a literal space too")
is5(k(SPACE), state.ERROR, false, false, false, "literal_space", "space in error: a literal space too")
is5(k(SPACE), state.IDLE, false, false, true, "noop", "space on unselected pinyin selects, natively")
is5(k(SPACE), state.RESULT, false, false, true, "invalidate_and_pass", "space on unselected pinyin in result: void, then select")
is5(k(SPACE), state.IDLE, true, false, false, "noop", "space with no draft is the application's")
is5(k(SPACE, SHIFT), state.IDLE, false, false, false, "noop", "shift-space is native")
is5(k(SPACE, SHIFT), state.RESULT, false, false, false, "invalidate_and_pass", "shift-space in result voids, then passes")
is5(k(SPACE, 0, true), state.IDLE, false, false, false, "noop", "a space release is never acted on")
```

In `tests/test_processor.lua`, the fake context gains what the Enter way reads
and writes. Replace its `composition = …` line:

```lua
    composition = {
      back = function() if ctx._text ~= "" then return ctx._seg end end,
      empty = function() return ctx._seg == nil end,
      toSegmentation = function() return ctx._segmentation end,
    },
    -- feature 002 (Task 7): clearing what is not confirmed leaves an empty
    -- segment at the confirmed position, or none when that is 0 (upstream
    -- F20, F23)
    clear_non_confirmed_composition = function(self)
      self.trace[#self.trace + 1] = "clear_non_confirmed"
      local cp = self._segmentation:get_confirmed_position()
      self._seg = cp > 0 and { prompt = "", start = cp, _end = cp } or nil
      return true
    end,
    push_input = function(self, s)
      self.trace[#self.trace + 1] = "push(" .. s .. ")"
      self.input = self.input .. s
      self.caret_pos = #self.input
    end,
```

and, after the line `ctx._seg = seg`, add:

```lua
  -- _confirmed is the composition's confirmed position; nil means all of the
  -- input, i.e. nothing unselected (feature 002, Task 7)
  ctx._segmentation = {
    get_confirmed_position = function() return ctx._confirmed or #ctx.input end,
    add_segment = function(_, s)
      ctx.trace[#ctx.trace + 1] = ("add(%d,%d)"):format(s.start, s._end)
      ctx._seg = s
      return true
    end,
  }
```

Then append, just before its final `print(...)`:

```lua
---------- feature 002 (design §5.5): the Enter way ----------
local SPACE = 0x20
-- librime-lua's Segment(start, end), faked
Segment = function(s, e) return { start = s, _end = e, prompt = "" } end

-- Enter with unselected pinyin after a selection: one bare segment over it,
-- confirmed; nothing committed, nothing translated, the mode untouched
env, ctx, seg = fake("今天热爱多么", "jintianreadme")
ctx._confirmed = 7
calls = {}
eq(press(env, RET), kAccepted, "enter on unselected pinyin is taken")
eq(trace(ctx), "clear_non_confirmed,confirm", "the unselected part is cleared, then confirmed bare")
eq(ctx._seg.start, 7, "the bare segment starts at the confirmed position")
eq(ctx._seg._end, 13, "and covers the rest of the input")
eq(ctx._seg.length, 6, "with its length set, so a reopen keeps it")
eq(#env.committed, 0, "nothing committed")
eq(#calls, 0, "nothing translated")
eq(ctx.input, "jintianreadme", "the input is intact")
eq(ctx.opts.ascii_mode, nil, "the mode is not touched")

-- all of the input unselected: the composition is left empty, and a segment
-- is added at 0
env, ctx, seg = fake("热爱多么", "readme")
ctx._confirmed = 0
press(env, RET)
eq(trace(ctx), "clear_non_confirmed,add(0,0),confirm", "an empty composition gets a segment first")
eq(ctx._seg._end, 6, "which covers the whole input")

-- the segment cannot be added: nothing is confirmed, nothing committed
env, ctx, seg = fake("热爱多么", "readme")
ctx._confirmed = 0
ctx._segmentation.add_segment = function() return false end
eq(press(env, RET), kAccepted, "enter is still taken")
eq(trace(ctx), "clear_non_confirmed", "no confirm without the segment")
eq(#env.committed, 0, "and nothing committed")

-- the caret inside the input: the first Enter only moves it (§5.2)
env, ctx, seg = fake("今天天气很", "jintiantianqihenhao")
ctx._confirmed = 0
ctx.caret_pos = 5
press(env, RET)
eq(trace(ctx), "", "enter with the caret inside locks nothing")
eq(ctx.caret_pos, #ctx.input, "it only moves the caret to the end")

-- Shift+Enter on unselected pinyin still commits the draft as shown
env, ctx, seg = fake("今天热爱多么", "jintianreadme")
ctx._confirmed = 7
press(env, RET, SHIFT)
eq(env.committed[1], "今天热爱多么", "shift-enter commits the draft, as before")

-- Space with nothing unselected: a literal space, confirmed
env, ctx, seg = fake("今天readme", "jintianreadme")
eq(press(env, SPACE), kAccepted, "space with nothing unselected is taken")
eq(trace(ctx), "push( ),confirm", "a space is pushed, then confirmed")
eq(ctx.input, "jintianreadme ", "the space is in the input")
eq(#env.committed, 0, "nothing committed")
-- with unselected pinyin, Space is native: it selects
env, ctx, seg = fake("今天好的", "jintianhaode")
ctx._confirmed = 7
eq(press(env, SPACE), kNoop, "space on unselected pinyin passes on")
eq(trace(ctx), "", "and pushes nothing")
-- with no draft, Space is the application's
env, ctx, seg = fake("")
eq(press(env, SPACE), kNoop, "space with no draft passes on")
-- with a translation on screen: it is voided first
env, ctx, seg = fake("今天有点累")
answer, calls = { true, "Tired" }, {}
press(env, RET)
eq(press(env, SPACE), kAccepted, "space in result is taken")
eq(seg.prompt, "", "the translation is dropped")
eq(ctx.input:sub(-1), " ", "and the space is in the input")
eq(#env.committed, 0, "nothing committed")
calls = {}
press(env, RET)
eq(#calls, 1, "the next enter translates the new draft")
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `lua tests/test_decide.lua; lua tests/test_processor.lua`
Expected: both FAIL.
- `test_decide` fails at the first new assertion,
  `#71 Space is 0x20: got "nil" want "32"`.
- `test_processor` fails at
  `#125 the unselected part is cleared, then confirmed bare: got "" want "clear_non_confirmed,confirm"`.
  Enter translates instead, which is also taken, so #124 passes.

- [ ] **Step 3: Implement `decide`**

In `rime/lua/ime_translate/decide.lua`, add the constant after
`M.RETURN, M.KP_ENTER, M.ESC = …`:

```lua
M.SPACE = 0x20
```

add two lines to the list of actions, after `invalidate_and_pass`:

```lua
--   lock_literal         the processor locks what is not yet selected as the
--                        letters typed (design §5.5)
--   literal_space        the processor adds a literal space to the draft (§5.5)
```

change the function head:

```lua
function M.decide(key, phase, draft_empty, draft_ascii, unselected)
```

in the plain-Enter branch, add one line before the `draft_ascii` line:

```lua
    -- design §5.5: unselected pinyin becomes the letters typed
    if unselected then return { type = "lock_literal" } end
```

and add the Space rule after the Shift+Enter branch, before the Esc rule:

```lua
  -- design §5.5: Space with a draft open and nothing unselected is a literal
  -- space. Natively it would commit the whole draft untranslated (F27).
  if code == M.SPACE and mods == 0 and not draft_empty and not unselected then
    return { type = "literal_space" }
  end
```

- [ ] **Step 4: Implement the processor**

In `rime/lua/ime_translate_processor.lua`, the two actions act on the draft,
so the caret rule covers them:

```lua
local ACTS_ON_DRAFT = { translate = true, commit_translation = true, commit_draft = true,
                        lock_literal = true, literal_space = true }
```

Replace the `decide` call with one that reads what is unselected:

```lua
  -- Feature 002 (design §5.5): is any of the input not yet selected?
  -- librime-lua reaches the confirmed position through toSegmentation()
  -- (upstream F27).
  local unselected = ctx.input ~= ""
    and ctx.composition:toSegmentation():get_confirmed_position() < #ctx.input
  local action = decide.decide(k, session.phase(ctx), ctx.input == "",
                               not draft:find("[\128-\255]"), unselected)
```

and add the two actions before the `invalidate_and_pass` branch:

```lua
  elseif action.type == "lock_literal" then
    -- Design §5.5: what is not yet selected becomes the letters typed. One
    -- bare segment over it, confirmed: a segment with no candidate is
    -- confirmed as raw input (upstream F20). The mode is not touched, so
    -- Squirrel shows no notice (F24). Nothing is committed or cleared.
    local comp = ctx.composition
    local segs = comp:toSegmentation()
    local start = segs:get_confirmed_position()
    ctx:clear_non_confirmed_composition()
    if comp:empty() or comp:back().start ~= start or comp:back()._end ~= start then
      segs:add_segment(Segment(start, start))
    end
    local last = not comp:empty() and comp:back()
    if not last or last.start ~= start then
      log(S, "lock literal: no segment to confirm")
      return kAccepted
    end
    last._end = #ctx.input
    last.length = #ctx.input - start
    ctx:confirm_current_selection()
    log(S, "lock literal")
    return kAccepted

  elseif action.type == "literal_space" then
    -- Design §5.5: a space into the draft, confirmed the same way. Natively
    -- Space with nothing left to select commits the whole draft untranslated
    -- (upstream F27). A space is an edit: a translation on screen goes first.
    session.clear(ctx)
    show(ctx, draft)
    ctx:push_input(" ")
    ctx:confirm_current_selection()
    log(S, "literal space")
    return kAccepted
```

- [ ] **Step 5: Run them and confirm they pass**

Run: `lua tests/test_decide.lua && lua tests/test_processor.lua && scripts/run_tests.sh`
Expected: `test_decide: 92 assertions OK`,
`test_processor: 152 assertions OK`, and every file PASS.

- [ ] **Step 6: Commit**

```bash
git add rime/lua/ime_translate/decide.lua rime/lua/ime_translate_processor.lua \
        tests/test_decide.lua tests/test_processor.lua
git commit -m "feat: Enter locks unselected pinyin as letters; Space adds a space"
```
