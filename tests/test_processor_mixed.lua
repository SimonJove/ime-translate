package.path = package.path .. ";rime/lua/?.lua;tests/?.lua"
-- The processor, feature 002 (design §5.5): the Shift tap, the Enter way, the
-- literal space.
-- The fake engine, the stubbed backend and the key helpers are in
-- processor_support.lua.
local T = require("processor_support")
local backend = require("ime_translate.backend")
local processor = require("ime_translate_processor")
local eq, fake, key, press, trace, tap = T.eq, T.fake, T.key, T.press, T.trace, T.tap
local kAccepted, kNoop = T.kAccepted, T.kNoop
local RET, SPACE = 0xFF0D, 0x20
local SHIFT, CTRL, REL = 0x1, 0x4, 1 << 30
local SHIFT_L, SHIFT_R = 0xFFE1, 0xFFE2
local env, ctx, seg
---------- feature 002 (design §5.5): the Shift tap ----------

-- a tap with a draft open: lock first, then switch; nothing committed
env, ctx, seg = fake("今天", "jintian")
T.calls = {}
local a, b = tap(env)
eq(a, kNoop, "the Shift press passes on")
eq(b, kAccepted, "the release of a lone tap is taken")
eq(trace(ctx), "confirm,ascii_mode=true", "the segment is locked, then the mode is English")
eq(#env.committed, 0, "a tap commits nothing")
eq(ctx._text, "今天", "a tap keeps the draft")
eq(ctx.input, "jintian", "and the input")
eq(#T.calls, 0, "a tap never translates")
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
T.answer, T.calls = { true, "Tired" }, {}
press(env, RET)
tap(env)
eq(seg.prompt, "", "the Shift press dropped the translation")
eq(trace(ctx), "confirm,ascii_mode=true", "and the tap locks and switches")
eq(#env.committed, 0, "nothing committed")
-- the tap locked the segment but left the draft as it was, so the
-- translation comes from the cache (feature 005): shown, never committed
press(env, RET)
eq(#T.calls, 1, "enter then shows the cached translation, with no request")
eq(seg.prompt, "  -> Tired", "it is shown again")
eq(#env.committed, 0, "the voided translation is never committed")

-- Shift held past 500 ms is a held Shift, not a tap (ascii_composer's rule,
-- upstream F18)
env, ctx, seg = fake("今天", "jintian")
processor(key(SHIFT_L, SHIFT), env)
T.clock = T.clock + 600
eq(processor(key(SHIFT_L, REL, true), env), kNoop, "a Shift held 600 ms passes on")
eq(trace(ctx), "", "a long hold switches nothing")

-- the Shift state is per input box (design §6.1): a press in one box and a
-- release in another is no tap
local env1 = fake("今天", "jintian")
local env2, ctx2 = fake("好的", "haode")
processor(key(SHIFT_L, SHIFT), env1)
eq(processor(key(SHIFT_L, REL, true), env2), kNoop, "a release in another box is not a tap")
eq(trace(ctx2), "", "the other box switches nothing")

-- after a selection that reached the end of the input, or a second tap, the
-- last segment is the empty one: the confirm returns false (upstream F20),
-- and the tap still switches (§15.5; 002 Task 4 review, yellow 1)
env, ctx, seg = fake("今天", "jintian")
ctx.confirms = false
tap(env)
eq(trace(ctx), "confirm,ascii_mode=true", "a confirm that finds only the empty segment still switches")

-- the Shift state is written only when there is some, not on every key
-- (review, green 2)
env, ctx, seg = fake("今天", "jintian")
local shift_writes, set_property = 0, ctx.set_property
ctx.set_property = function(self, name, v)
  if name == "ime_translate.shift_down" then shift_writes = shift_writes + 1 end
  return set_property(self, name, v)
end
press(env, string.byte("a"))
eq(shift_writes, 0, "a letter with no Shift pending writes no Shift state")

-- no clock: a librime-lua with rime_api but no get_time_ms, and none at all.
-- A tap still counts (review, green 1)
for _, api in ipairs({ {}, false }) do
  rime_api = api or nil
  env, ctx, seg = fake("今天", "jintian")
  tap(env)
  eq(trace(ctx), "confirm,ascii_mode=true",
     ("with no clock (rime_api %s) a tap still locks and switches"):format(api and "without get_time_ms" or "absent"))
end

-- a draft with no Chinese: Enter commits it as is (Task 2's rule, wired)
env, ctx, seg = fake("git status", "git status")
T.calls = {}
eq(press(env, RET), kAccepted, "enter on an English-only draft is taken")
eq(env.committed[1], "git status", "and commits it as is")
eq(#T.calls, 0, "with no backend call")
-- a mixed draft is translated whole, the English inside it included
env, ctx, seg = fake("用git提交README文件", "yonggittijiaoREADMEwenjian")
T.answer, T.calls = { true, "Use git to submit the README file" }, {}
press(env, RET)
eq(T.calls[1], "用git提交README文件", "a mixed draft goes to the backend whole")
eq(seg.prompt, "  -> Use git to submit the README file", "and its translation is shown")
eq(#env.committed, 0, "and nothing is committed yet")
---------- feature 002 (design §5.5): the Enter way ----------

-- Enter with unselected pinyin after a selection: one bare segment over it,
-- confirmed; nothing committed, nothing translated, the mode untouched
env, ctx, seg = fake("今天热爱多么", "jintianreadme")
ctx._confirmed = 7
T.calls = {}
eq(press(env, RET), kAccepted, "enter on unselected pinyin is taken")
eq(trace(ctx), "clear_non_confirmed,confirm", "the unselected part is cleared, then confirmed bare")
eq(ctx._seg.start, 7, "the bare segment starts at the confirmed position")
eq(ctx._seg._end, 13, "and covers the rest of the input")
eq(ctx._seg.length, 6, "with its length set, so a reopen keeps it")
eq(#env.committed, 0, "nothing committed")
eq(#T.calls, 0, "nothing translated")
eq(ctx.input, "jintianreadme", "the input is intact")
eq(ctx.opts.ascii_mode, nil, "the mode is not touched")
-- Feature 006 (design §5.5): the hint shows until the next key press
eq(ctx._seg.prompt, "  [en]", "the lock shows the hint after the letters")
eq(processor(key(RET, REL, true), env), kNoop, "the Enter's release passes on")
eq(ctx._seg.prompt, "  [en]", "and leaves the hint")
local locked = ctx._seg
eq(press(env, string.byte("h")), kNoop, "the next letter passes on")
eq(locked.prompt, "", "and the hint is gone before it does")
-- Enter right after the lock translates: the translation replaces the hint,
-- and the hint rule never clears a translation, so the next Enter commits it
env, ctx, seg = fake("今天readme", "jintianreadme")
ctx._confirmed = 7
press(env, RET)
eq(ctx._seg.prompt, "  [en]", "locked, with the hint")
ctx._confirmed = nil
T.answer, T.calls = { true, "Today's readme" }, {}
press(env, RET)
eq(#T.calls, 1, "enter after the lock translates")
eq(ctx._seg.prompt, "  -> Today's readme", "the translation replaces the hint")
eq(press(env, RET), kAccepted, "enter again")
eq(env.committed[1], "Today's readme", "commits it: the hint rule left the translation alone")

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
-- feature 006 review, yellow: a composition left empty with a draft still read
-- back must not break the hint rule on the next key
ctx._seg = nil
eq(press(env, string.byte("a")), kNoop, "a key after that still reaches the processor")

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
T.answer, T.calls = { true, "Tired" }, {}
press(env, RET)
eq(press(env, SPACE), kAccepted, "space in result is taken")
eq(seg.prompt, "", "the translation is dropped")
eq(ctx.input:sub(-1), " ", "and the space is in the input")
eq(#env.committed, 0, "nothing committed")
ctx._text = "今天有点累 "  -- the space is in the draft too, as the engine would have it
T.calls = {}
press(env, RET)
eq(#T.calls, 1, "the next enter translates the new draft")

-- Shift+Space with nothing unselected: a literal space, not the native commit
-- (review, yellow 2)
env, ctx, seg = fake("今天readme", "jintianreadme")
eq(press(env, SPACE, SHIFT), kAccepted, "shift-space with nothing unselected is taken")
eq(trace(ctx), "push( ),confirm", "a space is pushed, then confirmed")
eq(#env.committed, 0, "nothing committed")

-- English mode: the open part is letters already, so nothing is unselected.
-- Enter translates a draft with Chinese at once, and commits one without as is
-- (the user's decision, Task 7 review)
env, ctx, seg = fake("今天readme", "jintianreadme")
ctx.opts.ascii_mode, ctx._confirmed = true, 7
T.answer, T.calls = { true, "Today's readme" }, {}
eq(press(env, RET), kAccepted, "enter in English mode is taken")
eq(trace(ctx), "", "nothing is locked")
eq(T.calls[1], "今天readme", "the mixed draft is translated at once")
env, ctx, seg = fake("git status", "git status")
ctx.opts.ascii_mode, ctx._confirmed = true, 0
T.calls = {}
press(env, RET)
eq(env.committed[1], "git status", "an English-only draft in English mode commits as is")
eq(#T.calls, 0, "with no backend call")
-- and Space in English mode is a literal space, whatever is open
env, ctx, seg = fake("今天read", "jintianread")
ctx.opts.ascii_mode, ctx._confirmed = true, 7
eq(press(env, SPACE), kAccepted, "space in English mode is taken")
eq(trace(ctx), "push( ),confirm", "and pushes a space")

T.done("test_processor_mixed")
