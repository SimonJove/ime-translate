package.path = package.path .. ";rime/lua/?.lua"
-- The processor, driven headless through whole key sequences. A deviation from
-- Task 9's plan, whose only test is the load smoke test: this is the module
-- that commits, so its paths are pinned here rather than left to the machine.
local shared = require("ime_translate_shared")
local config = require("ime_translate.config")
local backend = require("ime_translate.backend")
local processor = require("ime_translate_processor")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

local kAccepted, kNoop = 1, 2
local RET, ESC, SHIFT = 0xFF0D, 0xFF1B, 0x1

-- No config file, no Keychain: shared is filled in, not ensured. The key is a
-- sentinel so that passing it on is observable.
shared.settings, shared.warnings = config.load(function() return nil end)
shared.api_key, shared.loaded = "k-sentinel", true

-- The backend is stubbed: each test sets the next answer, and every call is
-- recorded with all four arguments.
local answer, calls, args = { true, "Hello" }, {}, nil
backend.translate = function(settings, text, runner, key)
  calls[#calls + 1] = text
  args = { settings = settings, runner = runner, key = key }
  return answer[1], answer[2]
end

-- A fake engine and context. _text is what get_commit_text() returns; input is
-- the raw pinyin, with the caret at its end unless a test moves it. An empty
-- composition has no last segment. ctx:clear() asserts the red line itself:
-- some commit_text must have happened since the draft was last cleared
-- (design §6.3).
local function fake(text, input)
  local seg = { prompt = "" }
  local props = {}
  local env = { committed = {} }
  local ctx
  ctx = {
    _text = text,
    input = input or (text == "" and "" or "pinyin"),
    get_property = function(_, k) return props[k] or "" end,
    set_property = function(_, k, v) props[k] = v end,
    get_commit_text = function(self) return self._text end,
    opts = {}, trace = {},
    get_option = function(self, name) return self.opts[name] == true end,
    set_option = function(self, name, v)
      self.opts[name] = v
      self.trace[#self.trace + 1] = name .. "=" .. tostring(v)
    end,
    confirm_current_selection = function(self)
      self.trace[#self.trace + 1] = "confirm"
      return self.confirms ~= false
    end,
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
    clear = function(self)
      assert(env.uncommitted == false, "ctx:clear() with no commit_text before it")
      self._text, self.input, self.caret_pos, seg.prompt = "", "", 0, ""
      env.uncommitted = true
    end,
  }
  ctx.caret_pos = #ctx.input
  ctx._seg = seg                       -- a test may swap the last segment
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
  env.engine = {
    context = ctx,
    commit_text = function(_, s) env.committed[#env.committed + 1] = s; env.uncommitted = false end,
  }
  env.uncommitted = true
  return env, ctx, seg
end
local function key(code, mod, rel)
  return { keycode = code, modifier = mod or 0, release = function() return rel or false end }
end
local function press(env, code, mod) return processor(key(code, mod), env) end

-- Enter translates, shows the prompt, commits nothing
local env, ctx, seg = fake("今天有点累")
answer, calls = { true, "A bit tired today" }, {}
eq(press(env, RET), kAccepted, "enter is taken")
eq(calls[1], "今天有点累", "the draft went to the backend")
eq(args.settings, shared.settings, "the backend gets the loaded settings")
eq(args.runner, backend.real_runner, "the backend gets the real curl runner")
eq(args.key, "k-sentinel", "the backend gets the api key")
eq(seg.prompt, "  -> A bit tired today", "the translation is in the prompt")
eq(#env.committed, 0, "nothing committed on the first enter")
eq(ctx._text, "今天有点累", "the draft is intact")
-- Enter again commits the translation, then clears
eq(press(env, RET), kAccepted, "second enter is taken")
eq(env.committed[1], "A bit tired today", "the translation is committed")
eq(ctx._text, "", "the composition is cleared after the commit")
eq(#calls, 1, "no second backend call")
-- the next sentence starts from idle
ctx._text, ctx.input, ctx.caret_pos = "好的", "haode", 5
answer = { true, "OK" }
press(env, RET)
eq(seg.prompt, "  -> OK", "the second sentence translates, not commits")
eq(#env.committed, 1, "still one commit")

-- After a commit, the same sentence typed again must be translated again: a
-- phase left behind would match the old snapshot, and Enter would commit
-- English that was never shown for this draft.
env, ctx, seg = fake("今天有点累")
answer, calls = { true, "Tired" }, {}
press(env, RET); press(env, RET)
ctx._text, ctx.input, ctx.caret_pos = "今天有点累", "pinyin", 6
eq(press(env, RET), kAccepted, "the same sentence again is taken")
eq(#env.committed, 1, "and not committed on its first enter")
eq(#calls, 2, "it is translated again")
-- the same after a failure and a committed Chinese draft
env, ctx, seg = fake("今天有点累")
answer, calls = { false, "timeout" }, {}
press(env, RET); press(env, RET)
ctx._text, ctx.input, ctx.caret_pos = "今天有点累", "pinyin", 6
answer = { true, "Tired" }
press(env, RET)
eq(#env.committed, 1, "after an error commit, the same sentence is not committed again")
eq(#calls, 2, "it is translated again after an error commit")

-- an error keeps the draft and shows the reason; Enter then commits the Chinese
env, ctx, seg = fake("今天有点累")
answer, calls = { false, "timeout" }, {}
eq(press(env, RET), kAccepted, "enter is taken on failure too")
eq(seg.prompt, "  ✗ 翻译超时", "the reason is in the prompt")
eq(#env.committed, 0, "nothing committed on failure")
eq(press(env, RET), kAccepted, "enter in error is taken")
eq(env.committed[1], "今天有点累", "the chinese draft is committed")

-- Esc in the result phase drops the prompt and keeps the draft
env, ctx, seg = fake("今天有点累")
answer = { true, "Hi" }
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
calls = {}
eq(press(env, RET), kAccepted, "enter after that translates again")
eq(#calls, 1, "a fresh backend call, not a commit of the old one")
eq(#env.committed, 0, "the voided translation is never committed")

-- Check 2: the draft changes with no key event (a mouse click on a candidate).
-- The next Enter must translate the new draft, never commit the old English.
env, ctx, seg = fake("今天有点累")
answer, calls = { true, "Old" }, {}
press(env, RET)
ctx._text = "今天有点困"
answer = { true, "New" }
eq(press(env, RET), kAccepted, "enter after a mouse edit is taken")
eq(#env.committed, 0, "the stale translation is not committed")
eq(calls[2], "今天有点困", "the edited draft is translated")
eq(seg.prompt, "  -> New", "the new translation is shown")
-- a mouse edit followed by a non-Enter key clears the old prompt too
env, ctx, seg = fake("今天有点累")
press(env, RET)
ctx._text = "今天有点困"
press(env, string.byte("a"), 0)
eq(seg.prompt, "", "check 2 drops a prompt left over by a mouse edit")

-- Shift+Enter commits the Chinese in every phase, with no backend call
env, ctx, seg = fake("今天有点累")
calls = {}
eq(press(env, RET, SHIFT), kAccepted, "shift-enter in idle is taken")
eq(env.committed[1], "今天有点累", "shift-enter commits the draft")
eq(#calls, 0, "shift-enter never translates")
env, ctx, seg = fake("今天有点累")
answer = { true, "Hi" }
press(env, RET)
press(env, RET, SHIFT)
eq(env.committed[1], "今天有点累", "shift-enter in result commits the chinese, not the english")

-- An empty draft: Enter passes on to the application, nothing is called
env, ctx, seg = fake("")
calls = {}
eq(press(env, RET), kNoop, "enter with no draft passes on")
eq(#calls, 0, "no backend call without a draft")

-- Release events are never acted on
env, ctx, seg = fake("今天有点累")
calls = {}
eq(processor(key(RET, 0, true), env), kNoop, "a release passes on")
eq(#calls, 0, "a release never translates")

-- Caps Lock does not stop Enter from being taken (R15, masked in decide)
env, ctx, seg = fake("今天有点累")
answer, calls = { true, "Hi" }, {}
eq(press(env, RET, 0x2), kAccepted, "enter with caps lock is taken")
eq(#calls, 1, "and translates")

-- Task 9 review, red: with the caret inside the input the commit text stops at
-- the caret. Enter and Shift+Enter only move the caret to the end; nothing is
-- committed, cleared or translated until the whole draft is on screen.
env, ctx, seg = fake("今天天气很", "jintiantianqihenhao")
ctx.caret_pos = #"jintiantianqihen"
calls = {}
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
eq(#calls, 0, "and does not translate the part before the caret")
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
-- a caret moved inside with no key event while a translation shows: Enter
-- commits nothing, moves the caret and drops the prompt (Task 9 review, round 2)
env, ctx, seg = fake("今天有点累", "jintianyoudianlei")
answer = { true, "Hi" }
press(env, RET)
ctx.caret_pos = 3
eq(press(env, RET), kAccepted, "enter in result with the caret inside is taken")
eq(#env.committed, 0, "and does not commit the translation")
eq(ctx.caret_pos, #ctx.input, "the caret moved to the end")
eq(seg.prompt, "", "the prompt is dropped")

-- Task 9 review, yellow 1: a no-key edit (paging the candidate window) leaves
-- the prompt on screen; the Esc that follows is aimed at it and keeps the draft.
env, ctx, seg = fake("今天有点累")
answer = { true, "Hi" }
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
answer, calls = { true, "Today is just" }, {}
press(env, RET)
local after_click = { prompt = "" }
ctx._seg = after_click
eq(press(env, RET), kAccepted, "enter after the prompt vanished is taken")
eq(#env.committed, 0, "and commits nothing unseen")
eq(after_click.prompt, "  -> Today is just", "the translation is shown again")
eq(#calls, 1, "without a second backend call")
eq(press(env, RET), kAccepted, "the next enter")
eq(env.committed[1], "Today is just", "commits what is now on screen")

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
answer, calls = { true, "Today's readme" }, {}
eq(press(env, RET), kAccepted, "enter in English mode is taken")
eq(trace(ctx), "", "nothing is locked")
eq(calls[1], "今天readme", "the mixed draft is translated at once")
env, ctx, seg = fake("git status", "git status")
ctx.opts.ascii_mode, ctx._confirmed = true, 0
calls = {}
press(env, RET)
eq(env.committed[1], "git status", "an English-only draft in English mode commits as is")
eq(#calls, 0, "with no backend call")
-- and Space in English mode is a literal space, whatever is open
env, ctx, seg = fake("今天read", "jintianread")
ctx.opts.ascii_mode, ctx._confirmed = true, 7
eq(press(env, SPACE), kAccepted, "space in English mode is taken")
eq(trace(ctx), "push( ),confirm", "and pushes a space")
print(("test_processor: %d assertions OK"):format(n))
