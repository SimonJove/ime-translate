-- Translation backends: three adapters, a curl subprocess, error
-- classification. The runner is injectable so the tests never shell out.
local json = require("ime_translate.json")
local config = require("ime_translate.config")
local M = {}

-- runner contract: cmd -> (body, http_code, exit_code)
-- curl appends the status code on its own last line via -w, so 401/403/429 do
-- not get confused with transport failures.
function M.real_runner(cmd)
  local f = io.popen(cmd .. " 2>/dev/null", "r")
  if not f then return "", 0, -1 end
  local raw = f:read("*a") or ""
  local ok, _, code = f:close() -- Lua 5.4: true/nil, "exit"/"signal", code
  local exit_code = ok and 0 or (code or -1)
  local body, http = raw:match("^(.*)\n(%d%d%d)$")
  if not body then return raw, 0, exit_code end
  return body, tonumber(http), exit_code
end

-- An explicit class, not %s: %s is C's isspace(), which under a UTF-8 ctype on
-- macOS also matches 0xA0 -- the last byte of some CJK characters -- and would
-- cut a translation ending in one into invalid UTF-8.
local function trim(s) return (s:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")) end

-- A number with two decimals, by integer arithmetic. tostring() and %f follow
-- LC_NUMERIC: under a comma-decimal locale tostring(0.2) is "0,2", which makes
-- the whole request body invalid JSON. (timeout_s below is built the same way.)
-- A value with no integer representation (1e20, 1e999) raises in format();
-- translate turns that into http_error, the outcome a vendor's 400 would give.
local function decimal2(x)
  local n = math.floor(math.abs(x) * 100 + 0.5)
  return ("%s%d.%02d"):format(x < 0 and "-" or "", n // 100, n % 100)
end

M.adapters = {}

M.adapters.openai = {
  endpoint = function(s) return s.base_url .. "/chat/completions" end,
  headers = function(s, key)
    local h = { "Content-Type: application/json" }
    if key then h[#h + 1] = "Authorization: Bearer " .. key end
    return h
  end,
  body = function(s, text)
    return table.concat({
      '{"model": ', json.escape(s.model),
      ', "messages": [{"role": "system", "content": ', json.escape(s.prompt),
      '}, {"role": "user", "content": ', json.escape(text),
      -- temperature is carried by this adapter only (design §7.7)
      ']}], "temperature": ', decimal2(s.temperature), '}',
    })
  end,
  parse = function(d)
    local c1 = type(d.choices) == "table" and d.choices[1]
    if type(c1) ~= "table" or type(c1.message) ~= "table" then return nil end
    -- Cut off at the token limit: committing the part would lose the rest of
    -- the message, so it is a failure and the draft stays (design §8.1).
    if c1.finish_reason == "length" then return nil end
    local c = c1.message.content
    return type(c) == "string" and c or nil
  end,
}

M.adapters.libretranslate = {
  endpoint = function(s) return s.base_url .. "/translate" end,
  headers = function() return { "Content-Type: application/json" } end,
  -- NMT: no prompt, no temperature. The language identifier is zh, not zh-Hans.
  body = function(s, text)
    return table.concat({ '{"q": ', json.escape(text),
                          ', "source": "zh", "target": "en", "format": "text"}' })
  end,
  parse = function(d)
    return type(d.translatedText) == "string" and d.translatedText or nil
  end,
}

M.adapters.anthropic = {
  endpoint = function(s) return s.base_url .. "/messages" end,
  headers = function(s, key)
    return { "Content-Type: application/json",
             "x-api-key: " .. (key or ""),
             -- Required header; omitting it fails the whole request
             "anthropic-version: 2023-06-01" }
  end,
  body = function(s, text)
    -- system is a top-level field, not part of messages; max_tokens is
    -- mandatory; temperature is not sent.
    return table.concat({
      '{"model": ', json.escape(s.model),
      ', "max_tokens": ', tostring(math.floor(s.max_tokens)),
      ', "system": ', json.escape(s.prompt),
      ', "messages": [{"role": "user", "content": ', json.escape(text), '}]}',
    })
  end,
  parse = function(d)
    -- max_tokens: cut off, the same failure as openai's finish_reason "length"
    if d.stop_reason == "refusal" or d.stop_reason == "max_tokens" then return nil end
    if type(d.content) ~= "table" then return nil end
    -- Walk for the type == "text" block: a thinking block can come first.
    for _, blk in ipairs(d.content) do
      if type(blk) == "table" and blk.type == "text" and type(blk.text) == "string" then
        return blk.text
      end
    end
    return nil
  end,
}

local function translate(settings, text, runner, api_key)
  -- Count characters. Lua's #s is bytes and a Chinese character is 3 bytes in
  -- UTF-8, so using it directly turns max_chars=2000 into roughly 666.
  -- utf8.len returns nil on an invalid sequence, so fall back to byte length.
  if (utf8.len(text) or #text) > settings.max_chars then return false, "too_long" end

  local ad = M.adapters[settings.backend]
  if not ad then return false, "http_error" end

  -- curl takes fractional seconds. Flooring to whole seconds would turn the
  -- 1500 ms default into a 1 s ceiling, and design §8.2 says this number IS the
  -- worst-case freeze. Integer arithmetic keeps the decimal point locale-proof.
  -- config.load bounds timeout_ms to [500, 10000], so 0 (curl: no limit) cannot
  -- arrive here.
  local ms = math.floor(settings.timeout_ms)
  local timeout_s = ("%d.%03d"):format(ms // 1000, ms % 1000)
  -- -q (valid only as the first argument): ignore ~/.curlrc. An "include" there
  -- turns every success into bad_json, "fail" hides a 401, and "retry" stretches
  -- the freeze past timeout_ms.
  -- --globoff: curl expands {a,b} and [a-b] in a URL before parsing it, so a
  -- base_url carrying one is several requests. config.load refuses such a URL
  -- for loopback but keeps it under allow_remote, so for a remote URL this is
  -- the only layer.
  -- No --connect-timeout: --max-time already bounds the whole request, and a
  -- separate handshake limit would cut a slow cloud TLS setup below timeout_ms.
  local parts = { "curl", "-q", "-sS", "--globoff",
                  "-w", json.shq("\\n%{http_code}"),
                  "--max-time " .. timeout_s,
                  json.shq(ad.endpoint(settings)) }
  -- A loopback request must never be routed through a proxy. Remote requests
  -- keep the environment's proxy settings, NO_PROXY included.
  if config.is_loopback(settings.base_url) then
    parts[#parts + 1] = "--noproxy"
    parts[#parts + 1] = json.shq("*")
  end
  for _, h in ipairs(ad.headers(settings, api_key)) do
    parts[#parts + 1] = "-H"
    parts[#parts + 1] = json.shq(h)
  end
  parts[#parts + 1] = "-d"
  parts[#parts + 1] = json.shq(ad.body(settings, text))

  local body, http, exit_code = runner(table.concat(parts, " "))
  if exit_code == 7 then return false, "conn_refused" end
  if exit_code == 28 then return false, "timeout" end
  if exit_code ~= 0 then return false, "http_error" end
  if http == 401 or http == 403 then return false, "auth_error" end
  if http == 429 then return false, "rate_limited" end
  if http and http >= 400 then return false, "http_error" end
  if not body or #body == 0 then return false, "http_error" end

  local data = json.decode(body)
  if type(data) ~= "table" then return false, "bad_json" end
  local out = ad.parse(data)
  if type(out) ~= "string" or trim(out) == "" then return false, "empty" end
  return true, trim(out)
end

-- The contract is (ok, translation_or_errcode), never a raise: the processor
-- calls this without pcall, and what librime-lua does with a raising processor
-- is unverified. A raise here is a failed translation, and the draft stays.
function M.translate(settings, text, runner, api_key)
  local ok, a, b = pcall(translate, settings, text, runner, api_key)
  if not ok then return false, "http_error" end
  return a, b
end

-- No-op in v1 (design §8.3). The hook point for pre-translation is decided --
-- the processor's invalidate branch -- but v1 does not wire it: hits are not
-- guaranteed (one character changing at the end of the draft expires the
-- result), and cloud pre-translation would also send drafts the user never
-- commits, a larger privacy surface than "send on Enter".
function M.prewarm(settings, text, runner) return nil end

return M
