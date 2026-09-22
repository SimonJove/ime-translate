# Task 6: Backend adapters (TDD)

**Files:**
- Create: `rime/lua/ime_translate/backend.lua`
- Test: `tests/test_backend.lua`

**Interfaces:**
- Consumes: `json.escape/shq/decode` (Tasks 2/3); `settings` (Task 5)
- Produces:
  - `backend.real_runner(cmd) -> body, http_code, exit_code`
  - `backend.translate(settings, text, runner, api_key) -> ok, translation_or_errcode`
  - `backend.prewarm(settings, text, runner) -> nil` — **a no-op in v1**, see
    design §8.3
  - `backend.adapters` — `openai` / `libretranslate` / `anthropic`, each with
    `endpoint(settings)` / `headers(settings, key)` / `body(settings, text)` /
    `parse(data)`

- [ ] **Step 1: Write the failing test**

`tests/test_backend.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local backend = require("ime_translate.backend")
local config = require("ime_translate.config")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end
local function S(text) return (config.load(function() return text end)) end
-- runner contract: returns (body, http_code, exit_code)
local function fake(body, http, exit)
  return function() return body, http or 200, exit or 0 end
end

---------- openai adapter ----------
local s_oa = S(nil)
local seen
local ok, tr = backend.translate(s_oa, "收到，我马上看", function(cmd)
  seen = cmd
  return '{"choices":[{"message":{"content":"  Received, will check soon. "}}]}', 200, 0
end)
eq(ok, true, "openai success")
eq(tr, "Received, will check soon.", "content trimmed")
assert(seen:find("chat/completions"), "openai hits chat/completions")
assert(seen:find("%-%-max%-time 1%.500"), "curl max-time carries timeout_ms exactly: 1500 -> 1.500")
assert(seen:find('"temperature": 0%.2'), "openai carries temperature")

-- JSON escaping reaches the body
backend.translate(s_oa, '含"引号"与\n换行', function(cmd)
  seen = cmd; return '{"choices":[{"message":{"content":"y"}}]}', 200, 0
end)
assert(seen:find('含\\"引号\\"'), "user text json-escaped")
assert(seen:find("\\n"), "newline escaped in body")

---------- libretranslate adapter ----------
local s_lt = S("backend: libretranslate\nbase_url: http://127.0.0.1:8989\n")
local ok2, tr2 = backend.translate(s_lt, "收到", function(cmd)
  seen = cmd; return '{"translatedText":"Got it."}', 200, 0
end)
eq(ok2, true, "libretranslate success")
eq(tr2, "Got it.", "translatedText extracted")
assert(seen:find("/translate"), "libretranslate hits /translate")
assert(seen:find('"source": "zh"') or seen:find('"source":"zh"'), "source zh not zh-Hans")
assert(not seen:find("temperature"), "NMT carries no temperature")

---------- anthropic adapter ----------
local s_an = S("backend: anthropic\nallow_remote: true\n" ..
               "base_url: https://api.anthropic.com/v1\nmodel: claude-haiku-4-5\n" ..
               "api_key_account: anthropic\n")
local ok3, tr3 = backend.translate(s_an, "收到", function(cmd)
  seen = cmd
  -- The thinking block comes before the text block: never take content[0].
  return '{"content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"Got it."}],' ..
         '"stop_reason":"end_turn"}', 200, 0
end, "sk-test-key")
eq(ok3, true, "anthropic success")
eq(tr3, "Got it.", "text block found past leading thinking block")
assert(seen:find("/messages"), "anthropic hits /messages")
assert(seen:find("x%-api%-key: sk%-test%-key"), "x-api-key header")
assert(seen:find("anthropic%-version: 2023%-06%-01"), "required version header")
assert(seen:find('"system":'), "system is a top-level field")
assert(seen:find('"max_tokens":'), "max_tokens is mandatory")
assert(not seen:find("temperature"), "anthropic carries no temperature")

-- refusal
eq(select(2, backend.translate(s_an, "x",
  fake('{"content":[{"type":"text","text":"no"}],"stop_reason":"refusal"}'), "k")),
  "empty", "anthropic refusal -> empty")

---------- error classification ----------
eq(select(2, backend.translate(s_oa, "x", fake("", 0, 7))),   "conn_refused", "curl exit 7")
eq(select(2, backend.translate(s_oa, "x", fake("", 0, 28))),  "timeout", "curl exit 28")
eq(select(2, backend.translate(s_oa, "x", fake("", 0, 6))),   "http_error", "other curl exit")
eq(select(2, backend.translate(s_oa, "x", fake("{}", 401))),  "auth_error", "401")
eq(select(2, backend.translate(s_oa, "x", fake("{}", 403))),  "auth_error", "403")
eq(select(2, backend.translate(s_oa, "x", fake("{}", 429))),  "rate_limited", "429")
eq(select(2, backend.translate(s_oa, "x", fake("{}", 500))),  "http_error", "500")
eq(select(2, backend.translate(s_oa, "x", fake("not json", 200))), "bad_json", "garbage body")
eq(select(2, backend.translate(s_oa, "x", fake("", 200))),    "http_error", "empty body")
eq(select(2, backend.translate(s_oa, "x",
  fake('{"choices":[{"message":{"content":"   "}}]}'))), "empty", "whitespace-only content")
eq(select(2, backend.translate(s_oa, "x", fake('{"choices":[]}'))), "empty", "no choices")

---------- max_chars counts characters ----------
eq(select(2, backend.translate(s_oa, ("长"):rep(2001), fake("{}"))), "too_long", "over max_chars")
-- 700 Chinese characters = 2100 bytes; counting bytes would wrongly reject this
eq(select(1, backend.translate(s_oa, ("长"):rep(700),
  fake('{"choices":[{"message":{"content":"ok"}}]}'))), true, "700 chars is not too long")

---------- prewarm is a no-op ----------
local called = false
eq(backend.prewarm(s_oa, "any text", function() called = true end), nil, "prewarm returns nil")
eq(called, false, "prewarm v1 does not call runner")

---------- the key must never appear in a return value ----------
local _, e = backend.translate(s_an, "x", fake("{}", 401), "sk-secret")
assert(not tostring(e):find("sk%-secret"), "errcode never leaks the key")
print(("test_backend: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_backend.lua`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement**

`rime/lua/ime_translate/backend.lua`:

```lua
-- Translation backends: three adapters, a curl subprocess, error
-- classification. The runner is injectable so the tests never shell out.
local json = require("ime_translate.json")
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

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

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
      ']}], "temperature": ', tostring(s.temperature), '}',
    })
  end,
  parse = function(d)
    local c = d.choices and d.choices[1] and d.choices[1].message
              and d.choices[1].message.content
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
    if d.stop_reason == "refusal" then return nil end
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

function M.translate(settings, text, runner, api_key)
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
  local parts = { "curl", "-sS", "-w", json.shq("\\n%{http_code}"),
                  "--connect-timeout 1", "--max-time " .. timeout_s,
                  json.shq(ad.endpoint(settings)) }
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

-- No-op in v1 (design §8.3). The hook point for pre-translation is decided --
-- the processor's invalidate branch -- but v1 does not wire it: hits are not
-- guaranteed (one character changing at the end of the draft expires the
-- result), and cloud pre-translation would also send drafts the user never
-- commits, a larger privacy surface than "send on Enter".
function M.prewarm(settings, text, runner) return nil end

return M
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `lua tests/test_backend.lua && scripts/run_tests.sh`
Expected: everything PASS

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/backend.lua tests/test_backend.lua
git commit -m "feat: backend adapters and error classification"
```
