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
-- Deviation (a): decision D4 made translate the default, so S(nil) is now the
-- libretranslate adapter. The openai adapter is configured explicitly.
local s_oa = S("backend: openai\nbase_url: http://127.0.0.1:11434/v1\nmodel: apple-foundationmodel\n")
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
---------- deviations from the plan (review-log, Task 6) ----------
local ADAPTERS = { openai = s_oa, libretranslate = s_lt, anthropic = s_an }

-- (b) curl expands {a,b} and [a-b] globs in a URL before parsing it, so a
-- base_url carrying one is several requests (Task 5's review); and a loopback
-- request must never be routed through a proxy, while a remote one keeps the
-- environment's proxy settings, NO_PROXY included (Task 6 review, green 1).
-- -q must come first or curl reads ~/.curlrc (yellow 2); there is no separate
-- handshake limit below timeout_ms (green 2).
for name, s in pairs(ADAPTERS) do
  backend.translate(s, "x", function(cmd) seen = cmd; return "{}", 200, 0 end, "k")
  eq(seen:sub(1, 8), "curl -q ", name .. ": -q is curl's first argument")
  eq(seen:find("%-%-globoff") ~= nil, true, name .. ": curl gets --globoff")
  eq(seen:find("%-%-noproxy '%*'") ~= nil, name ~= "anthropic",
     name .. ": --noproxy exactly when base_url is loopback")
  eq(seen:find("connect%-timeout") == nil, true, name .. ": no --connect-timeout")
end

-- (c) trim must not follow the locale: %s matches 0xA0 under a UTF-8 ctype on
-- macOS -- the last byte of U+4E20 -- and cut a translation ending in it.
local UTF8 = os.setlocale("en_US.UTF-8", "ctype") or os.setlocale("C.UTF-8", "ctype")
if not UTF8 then io.stderr:write("note: no UTF-8 ctype here; the trim test ran under C\n") end
local tail = "Done \228\184\160"
eq(select(2, backend.translate(s_lt, "x", fake('{"translatedText":"  ' .. tail .. ' "}'))), tail,
   "trim keeps a trailing 0xA0 byte under a UTF-8 ctype")
os.setlocale("C", "ctype")

-- (d) temperature must not follow LC_NUMERIC: tostring(0.2) is "0,2" under a
-- comma-decimal locale, and the whole body becomes invalid JSON.
local NUM = os.setlocale("de_DE.UTF-8", "numeric") or os.setlocale("fr_FR.UTF-8", "numeric")
if not NUM then io.stderr:write("note: no comma-decimal locale here; the temperature test ran under C\n") end
backend.translate(s_oa, "x", function(cmd) seen = cmd; return "{}", 200, 0 end)
eq(seen:find('"temperature": 0%.20') ~= nil, true, "temperature rendered with a dot under any LC_NUMERIC")
os.setlocale("C", "numeric")

-- (e) acceptance item 2 names three adapters x eight codes; the plan drove the
-- codes through the openai adapter only.
local CASES = {
  { "conn_refused", "x", fake("", 0, 7) },       { "timeout", "x", fake("", 0, 28) },
  { "http_error", "x", fake("{}", 500) },        { "bad_json", "x", fake("not json", 200) },
  { "empty", "x", fake("{}", 200) },             { "too_long", ("长"):rep(2001), fake("{}") },
  { "auth_error", "x", fake("{}", 401) },        { "rate_limited", "x", fake("{}", 429) },
}
for name, s in pairs(ADAPTERS) do
  for _, c in ipairs(CASES) do
    local ok_, code = backend.translate(s, c[2], c[3], "k")
    eq(ok_, false, name .. " x " .. c[1] .. ": fails")
    eq(code, c[1], name .. " x " .. c[1])
  end
end

---------- Task 6 review, round 1 ----------

-- (yellow 1) translate returns a code, never raises. Six openai bodies used to
-- raise in parse; a temperature with no integer representation raised in the
-- body. Each is a failed translation now.
for _, body in ipairs({ '{"choices":1}', '{"choices":true}', '{"choices":[1]}',
                        '{"choices":[true]}', '{"choices":[{"message":1}]}',
                        '{"choices":[{"message":true}]}' }) do
  local ok_, code = backend.translate(s_oa, "x", fake(body))
  eq(ok_, false, "openai " .. body .. ": fails")
  eq(code, "empty", "openai " .. body .. ": empty, not a raise")
end
for _, t in ipairs({ "1e20", "1e999", "-1e999" }) do
  local s_t = S("backend: openai\nbase_url: http://127.0.0.1:11434/v1\nmodel: m\ntemperature: " .. t .. "\n")
  local called = false
  local ok_, code = backend.translate(s_t, "x", function() called = true; return "{}", 200, 0 end)
  eq(code, "http_error", "temperature " .. t .. ": http_error, not a raise")
  eq(called, false, "temperature " .. t .. ": nothing is sent")
end

-- (yellow 4) a translation cut off at the token limit is a failure: committing
-- it would lose the rest of the message.
eq(select(2, backend.translate(s_an, "x",
  fake('{"content":[{"type":"text","text":"The first half of"}],"stop_reason":"max_tokens"}'), "k")),
  "empty", "anthropic max_tokens -> empty")
eq(select(2, backend.translate(s_oa, "x",
  fake('{"choices":[{"message":{"content":"The first half of"},"finish_reason":"length"}]}'))),
  "empty", "openai finish_reason length -> empty")
eq(select(2, backend.translate(s_oa, "x",
  fake('{"choices":[{"message":{"content":"Whole."},"finish_reason":"stop"}]}'))),
  "Whole.", "openai finish_reason stop is a translation")

-- (yellow 3) real_runner, with shell commands standing in for curl: no network.
-- It splits the status code off the last line and reports curl's exit code.
local function rr(cmd) return table.pack(backend.real_runner(cmd)) end
local r = rr([[printf '{"a":1}\n401']])
eq(r[1], '{"a":1}', "real_runner: body"); eq(r[2], 401, "real_runner: status"); eq(r[3], 0, "real_runner: exit 0")
r = rr([[printf 'a\nb\n200']])
eq(r[1], "a\nb", "real_runner: splits at the last newline"); eq(r[2], 200, "real_runner: status after a multi-line body")
r = rr([[printf partial; exit 28]])
eq(r[1], "partial", "real_runner: no status line keeps the body"); eq(r[2], 0, "real_runner: no status")
eq(r[3], 28, "real_runner: exit 28 (timeout)")
eq(rr("exit 7")[3], 7, "real_runner: exit 7 (connection refused)")
eq(rr("kill -9 $$")[3] ~= 0, true, "real_runner: a signal is not success")

-- (green 3) shell quoting, end to end: the built command goes through /bin/sh
-- with curl replaced by printf, and every argument must come back byte for byte.
-- The key travels in a header, so a quoting slip there is the one that matters.
local nasty = [[it's $(echo pwned) `id` "q" \ $HOME]]
-- allow_remote accepts any https URL, shell syntax included
local s_url = S("allow_remote: true\nbackend: openai\nmodel: m\n" ..
                "base_url: https://api.example.com/v1/$(echo pwned)`id`\n")
eq(s_url.base_url, "https://api.example.com/v1/$(echo pwned)`id`", "a remote URL with shell syntax loads")
for _, c in ipairs({ { "openai", s_oa }, { "anthropic", s_an }, { "openai", s_url } }) do
  local name, s = c[1], c[2]
  local cmd
  backend.translate(s, nasty, function(cm) cmd = cm; return "{}", 200, 0 end, nasty)
  local f = io.popen("printf '%s\\n'" .. cmd:sub(#"curl" + 1))
  local argv = {}
  for line in f:read("a"):gmatch("([^\n]*)\n") do argv[line] = true end
  f:close()
  local ad = backend.adapters[name]
  eq(argv[ad.endpoint(s)], true, name .. ": URL survives the shell: " .. s.base_url)
  eq(argv[ad.body(s, nasty)], true, name .. ": body survives the shell")
  local key_header = name == "openai" and "Authorization: Bearer " .. nasty or "x-api-key: " .. nasty
  eq(argv[key_header], true, name .. ": key header survives the shell")
end
-- openai sends the key only when there is one
backend.translate(s_oa, "x", function(c) seen = c; return "{}", 200, 0 end)
eq(seen:find("Authorization") == nil, true, "openai: no key, no Authorization header")

---------- hotfix 2026-09-22: every adapter's body is valid JSON ----------
-- The tests above match substrings of the curl command, so an openai body no
-- JSON parser accepts passed them all. Each body is decoded here instead, and
-- the user's text must come back exactly.
local json = require("ime_translate.json")
local draft = '你好，"x"\n\\ tab\t'
for _, name in ipairs({ "openai", "anthropic", "libretranslate" }) do
  local s = ({ openai = s_oa, anthropic = s_an, libretranslate = s_lt })[name]
  local d, e = json.decode(backend.adapters[name].body(s, draft))
  eq(type(d), "table", name .. ": the request body is valid JSON (" .. tostring(e) .. ")")
  if name == "libretranslate" then
    eq(d.q, draft, name .. ": q is the draft, exactly")
  else
    eq(d.model, s.model, name .. ": model")
    eq(d.messages[#d.messages].role, "user", name .. ": the last message is the user's")
    eq(d.messages[#d.messages].content, draft, name .. ": its content is the draft, exactly")
  end
end

---------- feature 005 (backend.md §7.5): the URL guard ----------
-- translate glues a URL to its neighbours, so libretranslate is sent X_n
-- placeholders and the URLs are put back after. The guard itself is tested in
-- test_url_guard.lua; these cases go through translate.
local G1 = "https://github.com/foo/bar"
-- through translate, with the libretranslate adapter
local body_q
local okg, trg = backend.translate(s_lt, "看一下 " .. G1 .. " 这个仓库", function(cmd)
  body_q = cmd; return '{"translatedText":"Take a look at X_1 this repo"}', 200, 0
end)
eq(okg, true, "guarded translation succeeds")
eq(trg, "Take a look at " .. G1 .. " this repo", "the result carries the URL")
-- the body, decoded: the draft with the URL swapped, the Chinese kept (review, green)
local json = require("ime_translate.json")
local body = json.decode(body_q:match("%-d '(.*)'$"))
eq(body.q, "看一下 X_1 这个仓库", "the request's q is the guarded draft")
local okb, cb = backend.translate(s_lt, "看 " .. G1, fake('{"translatedText":"Look"}'))
eq(okb, false, "a dropped placeholder fails"); eq(cb, "bad_guard", "as bad_guard")
-- the LLM adapters send the URL as typed: their prompt keeps URLs (§7.4)
for _, s in ipairs({ s_oa, s_an }) do
  backend.translate(s, "看 " .. G1, function(c) seen = c; return "{}", 200, 0 end, "k")
  assert(seen:find(G1, 1, true) and not seen:find("X_1"), s.backend .. " is not guarded")
end

print(("test_backend: %d assertions OK"):format(n))
