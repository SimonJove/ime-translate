package.path = package.path .. ";rime/lua/?.lua;tests/?.lua"
-- The processor, driven headless through whole key sequences: Enter, Esc, the
-- two invalidation checks, the caret rule and the retry (features 001, 005).
-- This is the module that commits, so its paths are pinned here rather than
-- left to the machine.
-- The fake engine, the stubbed backend and the key helpers are in
-- processor_support.lua.
local T = require("processor_support")
local shared = require("ime_translate_shared")
local backend = require("ime_translate.backend")
local processor = require("ime_translate_processor")
local cache = require("ime_translate.cache")
local eq, fake, key, press = T.eq, T.fake, T.key, T.press
local kAccepted, kNoop = T.kAccepted, T.kNoop
local RET, ESC = 0xFF0D, 0xFF1B
local SHIFT = 0x1
local env, ctx, seg
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { true, "A bit tired today" }, {}
eq(press(env, RET), kAccepted, "enter is taken")
eq(T.calls[1], "今天有点累", "the draft went to the backend")
eq(T.args.settings, shared.settings, "the backend gets the loaded settings")
eq(T.args.runner, backend.real_runner, "the backend gets the real curl runner")
eq(T.args.key, "k-sentinel", "the backend gets the api key")
eq(seg.prompt, "  -> A bit tired today", "the translation is in the prompt")
eq(#env.committed, 0, "nothing committed on the first enter")
eq(ctx._text, "今天有点累", "the draft is intact")
-- Enter again commits the translation, then clears
eq(press(env, RET), kAccepted, "second enter is taken")
eq(env.committed[1], "A bit tired today", "the translation is committed")
eq(ctx._text, "", "the composition is cleared after the commit")
eq(#T.calls, 1, "no second backend call")
-- the next sentence starts from idle
ctx._text, ctx.input, ctx.caret_pos = "好的", "haode", 5
T.answer = { true, "OK" }
press(env, RET)
eq(seg.prompt, "  -> OK", "the second sentence translates, not commits")
eq(#env.committed, 1, "still one commit")

-- After a commit, the same sentence typed again must be translated again: a
-- phase left behind would match the old snapshot, and Enter would commit
-- English that was never shown for this draft.
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { true, "Tired" }, {}
press(env, RET); press(env, RET)
ctx._text, ctx.input, ctx.caret_pos = "今天有点累", "pinyin", 6
eq(press(env, RET), kAccepted, "the same sentence again is taken")
eq(#env.committed, 1, "and not committed on its first enter")
-- feature 005: the translation comes from the cache, and is shown first
eq(#T.calls, 1, "the cached translation is reused")
eq(seg.prompt, "  -> Tired", "and shown, not committed")
-- the same after a failure and a committed Chinese draft (Shift+Enter since
-- feature 005: Enter in error asks again)
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { false, "timeout" }, {}
press(env, RET); press(env, RET, SHIFT)
ctx._text, ctx.input, ctx.caret_pos = "今天有点累", "pinyin", 6
T.answer = { true, "Tired" }
press(env, RET)
eq(#env.committed, 1, "after an error commit, the same sentence is not committed again")
eq(#T.calls, 2, "it is translated again after an error commit")

-- an error keeps the draft and shows the reason; Enter then translates again
-- (feature 005), and Shift+Enter commits the Chinese
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { false, "timeout" }, {}
eq(press(env, RET), kAccepted, "enter is taken on failure too")
eq(seg.prompt, "  ✗ 翻译超时", "the reason is in the prompt")
eq(#env.committed, 0, "nothing committed on failure")
eq(press(env, RET), kAccepted, "enter in error is taken")
eq(#T.calls, 2, "enter in error asks again")
eq(#env.committed, 0, "and commits nothing")
eq(seg.prompt, "  ✗ 翻译超时", "the reason shows again")
T.answer = { true, "Tired" }
press(env, RET)
eq(#T.calls, 3, "an error is never cached: a third request")
eq(seg.prompt, "  -> Tired", "the retry's translation shows")
eq(#env.committed, 0, "still nothing committed")
press(env, RET)
eq(env.committed[1], "Tired", "the next enter commits it")
env, ctx, seg = fake("今天有点累")
T.answer = { false, "timeout" }
press(env, RET)
eq(press(env, RET, SHIFT), kAccepted, "shift-enter in error is taken")
eq(env.committed[1], "今天有点累", "shift-enter in error commits the chinese draft")
-- the caret rule holds in error: the first Enter only moves the caret
env, ctx, seg = fake("今天有点累", "jintianyoudianlei")
T.answer, T.calls = { false, "timeout" }, {}
press(env, RET)
ctx.caret_pos = 3
eq(press(env, RET), kAccepted, "enter in error with the caret inside is taken")
eq(ctx.caret_pos, #ctx.input, "it only moves the caret to the end")
eq(#T.calls, 1, "with no request")

-- Esc in the result phase drops the prompt and keeps the draft
env, ctx, seg = fake("今天有点累")
T.answer = { true, "Hi" }
press(env, RET)
eq(press(env, ESC), kAccepted, "esc in result is taken, not passed to native")
eq(seg.prompt, "", "esc drops the prompt")
eq(ctx._text, "今天有点累", "esc keeps the draft")
eq(#env.committed, 0, "esc commits nothing")
-- and in idle it goes to the native chain
eq(press(env, ESC), kNoop, "esc in idle passes")

-- Any other key in the result phase voids the display, then passes on
env, ctx, seg = fake("今天有点累")
press(env, RET)
eq(press(env, string.byte("a")), kNoop, "a letter passes on")
eq(seg.prompt, "", "and takes the prompt with it")
ctx._text = "今天有点累啊"  -- the letter edited the draft, as the engine would have it
T.calls = {}
eq(press(env, RET), kAccepted, "enter after that translates again")
eq(#T.calls, 1, "a fresh backend call, not a commit of the old one")
eq(#env.committed, 0, "the voided translation is never committed")

-- Check 2: the draft changes with no key event (a mouse click on a candidate).
-- The next Enter must translate the new draft, never commit the old English.
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { true, "Old" }, {}
press(env, RET)
ctx._text = "今天有点困"
T.answer = { true, "New" }
eq(press(env, RET), kAccepted, "enter after a mouse edit is taken")
eq(#env.committed, 0, "the stale translation is not committed")
eq(T.calls[2], "今天有点困", "the edited draft is translated")
eq(seg.prompt, "  -> New", "the new translation is shown")
-- a mouse edit followed by a non-Enter key clears the old prompt too
env, ctx, seg = fake("今天有点累")
press(env, RET)
ctx._text = "今天有点困"
press(env, string.byte("a"), 0)
eq(seg.prompt, "", "check 2 drops a prompt left over by a mouse edit")

-- Shift+Enter commits the Chinese in every phase, with no backend call
env, ctx, seg = fake("今天有点累")
T.calls = {}
eq(press(env, RET, SHIFT), kAccepted, "shift-enter in idle is taken")
eq(env.committed[1], "今天有点累", "shift-enter commits the draft")
eq(#T.calls, 0, "shift-enter never translates")
env, ctx, seg = fake("今天有点累")
T.answer = { true, "Hi" }
press(env, RET)
press(env, RET, SHIFT)
eq(env.committed[1], "今天有点累", "shift-enter in result commits the chinese, not the english")

-- An empty draft: Enter passes on to the application, nothing is called
env, ctx, seg = fake("")
T.calls = {}
eq(press(env, RET), kNoop, "enter with no draft passes on")
eq(#T.calls, 0, "no backend call without a draft")

-- Release events are never acted on
env, ctx, seg = fake("今天有点累")
T.calls = {}
eq(processor(key(RET, 0, true), env), kNoop, "a release passes on")
eq(#T.calls, 0, "a release never translates")

-- Caps Lock does not stop Enter from being taken (R15, masked in decide)
env, ctx, seg = fake("今天有点累")
T.answer, T.calls = { true, "Hi" }, {}
eq(press(env, RET, 0x2), kAccepted, "enter with caps lock is taken")
eq(#T.calls, 1, "and translates")

-- Task 9 review, red: with the caret inside the input the commit text stops at
-- the caret. Enter and Shift+Enter only move the caret to the end; nothing is
-- committed, cleared or translated until the whole draft is on screen.
env, ctx, seg = fake("今天天气很", "jintiantianqihenhao")
ctx.caret_pos = #"jintiantianqihen"
T.calls = {}
eq(press(env, RET, SHIFT), kAccepted, "shift-enter with the caret inside is taken")
eq(#env.committed, 0, "and commits nothing")
eq(ctx.input, "jintiantianqihenhao", "the input is kept whole")
eq(ctx.caret_pos, #"jintiantianqihenhao", "the caret moved to the end")
ctx._text = "今天天气很好"          -- the engine recomposes up to the new caret
eq(press(env, RET, SHIFT), kAccepted, "shift-enter again")
eq(env.committed[1], "今天天气很好", "now the whole draft is committed")
env, ctx, seg = fake("今天天气很", "jintiantianqihenhao")
ctx.caret_pos = 5
eq(press(env, RET), kAccepted, "enter with the caret inside is taken")
eq(#T.calls, 0, "and does not translate the part before the caret")
eq(ctx.caret_pos, #ctx.input, "the caret moved to the end")
-- caret at the very start: librime composes the whole input there (F15), but
-- the rule reads the caret -- one extra press, nothing lost
env, ctx, seg = fake("今天", "jintian")
ctx.caret_pos = 0
eq(press(env, RET, SHIFT), kAccepted, "shift-enter at the start is taken")
eq(#env.committed, 0, "and only moves the caret")
eq(ctx.caret_pos, 7, "the caret moved to the end")
eq(press(env, RET, SHIFT), kAccepted, "shift-enter again")
eq(env.committed[1], "今天", "commits the whole draft")
-- The caret rule covers exactly the actions that act on the whole draft
-- (refactor review, yellow). Space is one: with the caret inside, it only
-- moves the caret, and no space goes in at the caret.
env, ctx, seg = fake("今天有点累", "jintianyoudianlei")
ctx.caret_pos = 3
eq(press(env, 0x20), kAccepted, "space with the caret inside is taken")
eq(ctx.input, "jintianyoudianlei", "no space is pushed at the caret")
eq(ctx.caret_pos, #ctx.input, "the caret moved to the end")
-- The catch-all and Esc are not: Left passes on, Esc drops the prompt, and
-- neither moves the caret
env, ctx, seg = fake("今天有点累", "jintianyoudianlei")
T.answer = { true, "Tired" }
press(env, RET)
ctx.caret_pos = 3
eq(press(env, 0xFF51), kNoop, "Left in result with the caret inside passes on")
eq(ctx.caret_pos, 3, "and the caret stays for the native chain to move")
eq(seg.prompt, "", "the translation is voided")
ctx.caret_pos = #ctx.input
press(env, RET)
eq(seg.prompt, "  -> Tired", "translated again, with the caret at the end")
ctx.caret_pos = 3
eq(press(env, ESC), kAccepted, "Esc in result with the caret inside is taken")
eq(ctx.caret_pos, 3, "and does not move the caret")
eq(seg.prompt, "", "the prompt goes")
-- a caret moved inside with no key event while a translation shows: Enter
-- commits nothing, moves the caret and drops the prompt (Task 9 review, round 2)
env, ctx, seg = fake("今天有点累", "jintianyoudianlei")
T.answer = { true, "Hi" }
press(env, RET)
ctx.caret_pos = 3
eq(press(env, RET), kAccepted, "enter in result with the caret inside is taken")
eq(#env.committed, 0, "and does not commit the translation")
eq(ctx.caret_pos, #ctx.input, "the caret moved to the end")
eq(seg.prompt, "", "the prompt is dropped")

-- Task 9 review, yellow 1: a no-key edit (paging the candidate window) leaves
-- the prompt on screen; the Esc that follows is aimed at it and keeps the draft.
env, ctx, seg = fake("今天有点累")
T.answer = { true, "Hi" }
press(env, RET)
ctx._text = "今天有点类"
eq(press(env, ESC), kAccepted, "esc right after a no-key edit is taken")
eq(seg.prompt, "", "and drops the stale prompt")
eq(ctx._text, "今天有点类", "the draft is kept")
eq(#env.committed, 0, "nothing committed")
eq(press(env, ESC), kNoop, "the next esc is plain idle, native")
-- an Esc carrying the Caps Lock bit is taken the same way
env, ctx, seg = fake("今天有点累")
press(env, RET)
ctx._text = "今天有点类"
eq(press(env, ESC, 0x2), kAccepted, "esc with caps lock after a no-key edit is taken")
-- with the composition gone below Lua, Esc belongs to the application
env, ctx, seg = fake("今天有点累")
press(env, RET)
ctx._text, ctx.input, ctx.caret_pos = "", "", 0
eq(press(env, ESC), kNoop, "esc with no draft left passes on")

-- the composition emptied below Lua (focus loss): no segment, no error
env, ctx, seg = fake("今天有点累")
press(env, RET)
ctx._text, ctx.input, ctx.caret_pos = "", "", 0
eq(press(env, string.byte("a")), kNoop, "a key after the composition vanished passes on")

-- Task 10 smoke row 22 (observed by the agent): a click on the highlighted candidate
-- confirms the segment and opens an empty one after it. The prompt vanishes, the
-- draft does not change. Enter must show the translation again, never commit it
-- unseen; the next Enter commits.
env, ctx, seg = fake("今天不过")
T.answer, T.calls = { true, "Today is just" }, {}
press(env, RET)
local after_click = { prompt = "" }
ctx._seg = after_click
eq(press(env, RET), kAccepted, "enter after the prompt vanished is taken")
eq(#env.committed, 0, "and commits nothing unseen")
eq(after_click.prompt, "  -> Today is just", "the translation is shown again")
eq(#T.calls, 1, "without a second backend call")
eq(press(env, RET), kAccepted, "the next enter")
eq(env.committed[1], "Today is just", "commits what is now on screen")

T.done("test_processor")
