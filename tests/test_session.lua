package.path = package.path .. ";rime/lua/?.lua"
local session = require("ime_translate.session")
local state = require("ime_translate.state")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

-- A fake Context: a property table plus a mutable commit text. An unset key
-- reads as "", as the real engine returns it (Task 7 review, yellow 1).
local function fake_ctx(text)
  local props = {}
  return {
    _text = text or "",
    props = props,
    get_property = function(self, k) return props[k] or "" end,
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

-- a store that returns nil for an unset key (spike S4's fallback would) is idle too
local nilctx = fake_ctx("x")
nilctx.get_property = function() return nil end
eq(session.phase(nilctx), state.IDLE, "nil property reads as idle")

-- each setter clears the other phase's field, whatever came before (review, green)
local t = fake_ctx("今天")
session.set_error(t, "今天", "timeout"); session.set_result(t, "今天", "Today")
eq(session.code(t), "", "set_result clears an earlier error code")
session.set_error(t, "今天", "timeout")
eq(session.text(t), "", "set_error clears an earlier translation")
session.clear(t)
eq(session.code(t), "", "clear clears the error code")

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
print(("test_session: %d assertions OK"):format(n))
