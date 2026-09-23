package.path = package.path .. ";rime/lua/?.lua"
local state = require("ime_translate.state")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

eq(state.IDLE, "idle", "IDLE")
eq(state.RESULT, "result", "RESULT")
eq(state.ERROR, "error", "ERROR")
eq(state.BUSY, "busy", "BUSY constant kept but unreachable in v1")

eq(state.error_message("conn_refused"), "✗ 翻译服务未启动", "conn")
eq(state.error_message("timeout"), "✗ 翻译超时", "timeout")
eq(state.error_message("http_error"), "✗ 翻译失败", "http")
eq(state.error_message("bad_json"), "✗ 翻译失败", "json")
eq(state.error_message("empty"), "✗ 翻译失败", "empty")
eq(state.error_message("too_long"), "✗ 文本过长", "too long")
eq(state.error_message("auth_error"), "✗ 密钥无效", "auth")
eq(state.error_message("rate_limited"), "✗ 请求过频", "rate limit")
eq(state.error_message("bad_guard"), "✗ 翻译失败", "a URL guard failure (feature 005)")
eq(state.error_message("who_knows"), "✗ 翻译失败", "unknown code fallback")
eq(state.error_message(nil), "✗ 翻译失败", "nil code fallback")

-- The module must export no mutable state
eq(state.new, nil, "no FSM constructor")
eq(state.phase, nil, "no module-level phase")
-- Exactly these exports (from Task 4's review): state under any other name --
-- M.current with setters, M.sessions = {}, an exported messages table -- passed
-- the two checks above.
local want = { BUSY = "string", ERROR = "string", IDLE = "string", RESULT = "string",
               LOCK_HINT = "string", error_message = "function" }
local stray = {}
for k, v in pairs(state) do
  if want[k] ~= type(v) then stray[#stray + 1] = tostring(k) end
end
table.sort(stray)
eq(table.concat(stray, ","), "", "exports exactly the four constants, LOCK_HINT and error_message")
-- Feature 006 (design §5.5): the hint after Enter locks letters
eq(state.LOCK_HINT, "  [en]", "the lock hint")
print(("test_state: %d assertions OK"):format(n))
