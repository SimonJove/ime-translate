-- Phase constants and error strings. Stateless -- session state is session.lua.
local M = {}

M.IDLE, M.RESULT, M.ERROR = "idle", "result", "error"
-- Unreachable in v1: while blocking synchronously librime is single-threaded
-- and receives no keys at all, so busy can never be observed. The constant is
-- kept only so the semantics come back if an async route is taken later.
M.BUSY = "busy"

local messages = {
  conn_refused = "✗ 翻译服务未启动",
  timeout      = "✗ 翻译超时",
  http_error   = "✗ 翻译失败",
  bad_json     = "✗ 翻译失败",
  empty        = "✗ 翻译失败",
  too_long     = "✗ 文本过长",
  -- Cloud only. These two are separate codes because the user's action differs
  -- completely (fix the key vs wait); sharing "translation failed" would be the
  -- same as showing nothing.
  auth_error   = "✗ 密钥无效",
  rate_limited = "✗ 请求过频",
}

function M.error_message(code) return messages[code] or "✗ 翻译失败" end

return M
