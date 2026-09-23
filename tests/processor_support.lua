-- Shared by the test_processor*.lua files: a fake engine and context, the
-- stubbed backend, the key helpers and the assertion counter. Not a test file
-- itself (run_tests.sh runs tests/test_*.lua only).
package.path = package.path .. ";rime/lua/?.lua"
local shared = require("ime_translate_shared")
local config = require("ime_translate.config")
local backend = require("ime_translate.backend")
local processor = require("ime_translate_processor")
local cache = require("ime_translate.cache")

local T = { n = 0, kAccepted = 1, kNoop = 2 }

function T.eq(a, b, msg)
  T.n = T.n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(T.n, msg, tostring(a), tostring(b)))
end
function T.done(name) print(("%s: %d assertions OK"):format(name, T.n)) end

-- No config file, no Keychain: shared is filled in, not ensured. The key is a
-- sentinel so that passing it on is observable.
shared.settings, shared.warnings = config.load(function() return nil end)
shared.api_key, shared.loaded = "k-sentinel", true

-- The backend is stubbed: each test sets T.answer, and every call is recorded
-- in T.calls, the last one's arguments in T.args.
T.answer, T.calls, T.args = { true, "Hello" }, {}, nil
backend.translate = function(settings, text, runner, key)
  T.calls[#T.calls + 1] = text
  T.args = { settings = settings, runner = runner, key = key }
  return T.answer[1], T.answer[2]
end

-- librime-lua's clock (upstream F22), faked: every read is 10 ms after the one
-- before, and a test can jump T.clock
T.clock = 0
function T.use_clock()
  rime_api = { get_time_ms = function() T.clock = T.clock + 10; return T.clock end }
end
T.use_clock()

-- librime-lua's Segment(start, end), faked
Segment = function(s, e) return { start = s, _end = e, prompt = "" } end

-- A fake engine and context. _text is what get_commit_text() returns; input is
-- the raw pinyin, with the caret at its end unless a test moves it. An empty
-- composition has no last segment. ctx:clear() asserts the red line itself:
-- some commit_text must have happened since the draft was last cleared
-- (design §6.3).
function T.fake(text, input)
  -- Feature 005: a fresh translation cache for each case, so a request made
  -- by one case is never a hit in the next
  shared.cache = cache.new(32)
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
      -- empty exactly when back() has nothing to return, as in librime
      empty = function() return ctx._text == "" or ctx._seg == nil end,
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
function T.key(code, mod, rel)
  return { keycode = code, modifier = mod or 0, release = function() return rel or false end }
end
function T.press(env, code, mod) return processor(T.key(code, mod), env) end


function T.trace(c) return table.concat(c.trace, ",") end

-- A lone Shift tap in Squirrel's form (upstream F21): the press carries the
-- Shift bit, the release only the release bit. Returns both results.
local SHIFT, REL, SHIFT_L, ALT, ALT_R = 0x1, 1 << 30, 0xFFE1, 0x8, 0xFFEA
function T.tap(env, code)
  local a = processor(T.key(code or SHIFT_L, SHIFT), env)
  return a, processor(T.key(code or SHIFT_L, REL, true), env)
end

-- Feature 004: the switch is a lone Right Option tap, in Squirrel's form (F21,
-- F30): the press carries the Alt bit and passes on, the release only the
-- release bit. Returns what the release returned.
function T.otap(env)
  T.eq(processor(T.key(ALT_R, ALT), env), T.kNoop, "the Right Option press passes on")
  return processor(T.key(ALT_R, REL, true), env)
end

return T
