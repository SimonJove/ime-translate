package.path = package.path .. ";rime/lua/?.lua"
local decide = require("ime_translate.decide")
local state = require("ime_translate.state")
local n = 0
local function is(key, phase, empty, want, msg)
  n = n + 1
  local got = decide.decide(key, phase, empty).type
  assert(got == want, ("#%d %s: got %q want %q"):format(n, msg, got, want))
end
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

-- Deviation (Task 8 review, yellow 1): the key identities are literals, not the
-- module's own constants -- a mistyped constant would otherwise pass every test.
local RET, ESC, KP_ENTER = 0xFF0D, 0xFF1B, 0xFF8D
local SHIFT, LOCK, CTRL, ALT, SUPER = 0x1, 0x2, 0x4, 0x8, 1 << 26
eq(decide.RETURN, RET, "Return is 0xFF0D (spike: keycode 65293)")
eq(decide.ESC, ESC, "Esc is XK_Escape")
eq(decide.KP_ENTER, KP_ENTER, "keypad Enter is XK_KP_Enter")
eq(decide.SHIFT, SHIFT, "Shift is 0x1 (spike S14: mod=0x1)")

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
is(k(RET, SHIFT), state.IDLE, true, "noop", "empty draft + shift-return")

-- Enter across the three phases
is(k(RET), state.IDLE, false, "translate", "idle + draft -> translate")
is(k(RET), state.RESULT, false, "commit_translation", "result -> commit translation")
is(k(RET), state.ERROR, false, "translate", "error -> translate again (feature 005)")

-- Shift+Enter: commit the Chinese draft in all three phases
is(k(RET, SHIFT), state.IDLE, false, "commit_draft", "shift-return idle")
is(k(RET, SHIFT), state.RESULT, false, "commit_draft", "shift-return result")
is(k(RET, SHIFT), state.ERROR, false, "commit_draft", "shift-return error")

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

---------- deviations from the plan (review-log, Task 8 author's response) ----------

-- (yellow 1) Esc keeps the draft whatever the modifier: librime's Editor falls
-- back from Shift+Escape to Escape, which cancels the whole draft.
is(k(ESC, SHIFT), state.RESULT, false, "clear_display", "shift-esc in result")
is(k(ESC, CTRL), state.ERROR, false, "clear_display", "ctrl-esc in error")

-- (yellow 2) Caps Lock sets Lock on every key (spike R15). It must not change
-- a decision.
is(k(RET, LOCK), state.IDLE, false, "translate", "return+lock idle")
is(k(RET, LOCK), state.RESULT, false, "commit_translation", "return+lock result")
is(k(RET, LOCK), state.ERROR, false, "translate", "return+lock error: translate again")
is(k(RET, SHIFT | LOCK), state.ERROR, false, "commit_draft", "shift-return+lock error: the Chinese")
is(k(RET, LOCK), state.RESULT, true, "noop", "return+lock, empty draft")
is(k(RET, SHIFT | LOCK), state.IDLE, false, "commit_draft", "shift-return+lock idle")
is(k(RET, SHIFT | LOCK), state.RESULT, false, "commit_draft", "shift-return+lock result")
-- Super and Control are not Shift: they take no commit path, with Lock or without
is(k(RET, SUPER), state.RESULT, false, "invalidate_and_pass", "super-return in result")
is(k(RET, CTRL | LOCK), state.RESULT, false, "invalidate_and_pass", "ctrl-return+lock in result")

-- (yellow 3) keypad Enter is Enter
is(k(KP_ENTER), state.IDLE, false, "translate", "kp-enter idle")
is(k(KP_ENTER), state.RESULT, false, "commit_translation", "kp-enter result")
is(k(KP_ENTER), state.ERROR, false, "translate", "kp-enter error: translate again")
is(k(KP_ENTER), state.IDLE, true, "noop", "kp-enter, empty draft")
is(k(KP_ENTER, SHIFT), state.RESULT, false, "commit_draft", "shift-kp-enter result")
is(k(KP_ENTER, LOCK), state.RESULT, false, "commit_translation", "kp-enter+lock result")

-- (yellow 4, deferred to Task 10) Control+g is an ordinary key to decide: it
-- voids the result and passes on. key_binder's emacs_editing turning it into
-- Escape is the schema's to settle, not decide's.
local G = string.byte("g")
is(k(G, CTRL), state.RESULT, false, "invalidate_and_pass", "ctrl-g in result")

-- (green 2) an empty draft never commits, whatever a stale phase says
for _, ph in ipairs({ state.RESULT, state.ERROR }) do
  for _, code in ipairs({ RET, KP_ENTER }) do
    is(k(code), ph, true, "noop", ("enter %#x, empty draft, %s"):format(code, ph))
    is(k(code, SHIFT), ph, true, "noop", ("shift-enter %#x, empty draft, %s"):format(code, ph))
  end
end

-- (green 2) the catch-all, swept: every keycode that is not Enter or Esc,
-- under each modifier set, voids a translation and passes in result
-- and error, and is native in idle. The modifier keysyms 0xFFE1-0xFFEE are in
-- the range on purpose: exempting them is the key enumeration §6.2 rejects.
-- The rows §5.2 names, pinned one by one above; Lock never changes which.
local function named_row(code, m)
  local mods = m & ~LOCK
  if code == ESC then return true end
  if code == RET or code == KP_ENTER then return mods == 0 or mods == SHIFT end
  if code == 0x20 then return mods == 0 or mods == SHIFT end   -- feature 002: Space
  return false
end
-- CTRL | SHIFT: no Ctrl+Shift key is taken (feature 003 took B; 004 gave it back)
local MODSETS = { 0, SHIFT, LOCK, SHIFT | LOCK, CTRL, ALT, SUPER, CTRL | LOCK,
                  CTRL | SHIFT, CTRL | SHIFT | LOCK }
local WANT = { [state.RESULT] = "invalidate_and_pass", [state.ERROR] = "invalidate_and_pass",
               [state.IDLE] = "noop" }
local sweep, swept, bad = k(0), 0, nil
for code = 0, 0xFFFF do
  for _, m in ipairs(MODSETS) do
    if not named_row(code, m) then
      sweep.keycode, sweep.modifier = code, m
      for _, empty in ipairs({ false, true }) do
        -- feature 002 (review, yellow 1): the processor passes draft_ascii on
        -- every key, so the sweep runs with it both false and true
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
      end
    end
  end
end
eq(bad, nil, ("catch-all sweep, %d calls"):format(swept))

-- (green 1) purity, whole-surface: no call writes to the key, the module or
-- state -- no field changed, none added.
local function snap(t)
  local s = {}
  for kk, v in pairs(t) do s[#s + 1] = tostring(kk) .. "=" .. tostring(v) end
  table.sort(s)
  return table.concat(s, "\n")
end
local s_mod, s_state, key_changed = snap(decide), snap(state), nil
for _, ph in ipairs({ state.IDLE, state.RESULT, state.ERROR, state.BUSY }) do
  for _, code in ipairs({ RET, KP_ENTER, ESC, G, A }) do
    for _, m in ipairs(MODSETS) do
      for _, empty in ipairs({ false, true }) do
        local probe = k(code, m)
        local s_key = snap(probe)
        decide.decide(probe, ph, empty)
        if snap(probe) ~= s_key and not key_changed then
          key_changed = ("%#x mod %#x %s"):format(code, m, ph)
        end
      end
    end
  end
end
eq(key_changed, nil, "the key table is untouched")
eq(snap(decide), s_mod, "the module table is untouched")
eq(snap(state), s_state, "state is untouched")
---------- feature 002 (design §5.5): a draft with no Chinese ----------
local function is4(key, phase, empty, ascii, want, msg)
  n = n + 1
  local got = decide.decide(key, phase, empty, ascii).type
  assert(got == want, ("#%d %s: got %q want %q"):format(n, msg, got, want))
end
is4(k(RET), state.IDLE, false, true, "commit_draft", "enter, ascii draft: commit as is")
is4(k(KP_ENTER), state.IDLE, false, true, "commit_draft", "keypad enter, ascii draft")
is4(k(RET, LOCK), state.IDLE, false, true, "commit_draft", "enter+lock, ascii draft")
is4(k(RET), state.IDLE, false, false, "translate", "enter, draft with Chinese: translate")
is4(k(RET), state.IDLE, false, nil, "translate", "no flag: as before")
is4(k(RET), state.IDLE, true, true, "noop", "empty draft stays native")
is4(k(RET), state.RESULT, false, true, "commit_translation", "result is unchanged")
is4(k(RET), state.ERROR, false, true, "translate", "error translates again (feature 005)")
is4(k(RET, SHIFT), state.IDLE, false, true, "commit_draft", "shift-enter is unchanged")
is4(k(ESC), state.IDLE, false, true, "noop", "esc on an ascii draft stays native")
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
is5(k(RET), state.ERROR, false, false, true, "translate", "error translates again (feature 005)")
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
-- Shift+Space too: fluid_editor falls back from it to Space (review, yellow 2)
is5(k(SPACE, SHIFT), state.IDLE, false, false, false, "literal_space", "shift-space, nothing unselected: a literal space")
is5(k(SPACE, SHIFT), state.RESULT, false, false, false, "literal_space", "shift-space in result: a literal space")
is5(k(SPACE, SHIFT), state.IDLE, false, false, true, "noop", "shift-space on unselected pinyin selects, natively")
is5(k(SPACE, CTRL), state.IDLE, false, false, false, "noop", "control-space is native")
is5(k(SPACE, 0, true), state.IDLE, false, false, false, "noop", "a space release is never acted on")
---------- feature 004 (design §5.6): Ctrl+Shift+B is native again ----------
-- Feature 003 took it for the backend switch; feature 004 moved the switch to
-- a Right Option tap, which the processor watches, and gave the key back
local B, LOWER_B = 0x42, 0x62
for _, code in ipairs({ B, LOWER_B }) do
  for _, m in ipairs({ CTRL | SHIFT, CTRL | SHIFT | LOCK }) do
    is(k(code, m), state.IDLE, false, "noop", ("ctrl+shift+%#x in idle is native"):format(code))
    is(k(code, m), state.RESULT, false, "invalidate_and_pass", ("ctrl+shift+%#x in result voids and passes"):format(code))
    is(k(code, m), state.ERROR, false, "invalidate_and_pass", ("ctrl+shift+%#x in error voids and passes"):format(code))
  end
end
-- and no key or modifier set returns switch_backend: the action is gone
local ALT_R = 0xFFEA
is(k(ALT_R, ALT), state.IDLE, false, "noop", "a Right Option press is native in idle: the processor watches it")
is(k(ALT_R, ALT), state.RESULT, false, "invalidate_and_pass", "a Right Option press voids a translation")
is(k(ALT_R, 1 << 30, true), state.IDLE, false, "noop", "its release is noop in decide")
print(("test_decide: %d assertions OK"):format(n))
