package.path = package.path .. ";rime/lua/?.lua"
local json = require("ime_translate.json")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

eq(json.decode('"hi"'), "hi", "string")
eq(json.decode("42"), 42, "int")
eq(json.decode("-3.5"), -3.5, "negative float")
eq(json.decode("1e3"), 1000, "exponent")
eq(json.decode("true"), true, "true")
eq(json.decode("false"), false, "false")
eq(json.decode("null"), json.null, "null sentinel")
eq((json.decode('{"a":1}')).a, 1, "object")
eq((json.decode('[1,2,3]'))[2], 2, "array")
eq((json.decode('{"a":{"b":[{"c":"d"}]}}')).a.b[1].c, "d", "nested")
eq(json.decode('"\\u4e2d\\u6587"'), "中文", "bmp escape")
eq(json.decode('"\\ud83c\\udf89"'), "🎉", "surrogate pair")
eq(json.decode('"中文"'), "中文", "raw utf8")
eq((json.decode('  { "a" : 1 }  ')).a, 1, "leading/trailing whitespace")
eq(select(1, json.decode('{"a":1,}')), nil, "trailing comma rejected")
eq(select(1, json.decode('{"a":')), nil, "truncated rejected")
eq(select(1, json.decode('"unterminated')), nil, "unterminated string rejected")
eq(select(1, json.decode('"\\ud800"')), nil, "lone surrogate rejected")
eq(type(select(2, json.decode('{"a":'))), "string", "error is a message string")
eq((json.decode('{"e":""}')).e, "", "empty string value")

-- Real response shapes from OpenAI / Anthropic / LibreTranslate
local oa = json.decode('{"choices":[{"message":{"role":"assistant","content":"Got it."}}]}')
eq(oa.choices[1].message.content, "Got it.", "openai shape")
local an = json.decode('{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"Got it."}],"stop_reason":"end_turn"}')
eq(an.content[2].text, "Got it.", "anthropic shape with leading thinking block")
eq(an.content[1].type, "thinking", "thinking block is first")
local lt = json.decode('{"translatedText":"Got it."}')
eq(lt.translatedText, "Got it.", "libretranslate shape")

-- Full bodies (from Task 3's review): real replies carry null, [] and {} fields
-- the cut-down shapes above never reach. Written from the vendors' API docs.
local oa_full = json.decode('{"id":"chatcmpl-1","object":"chat.completion","created":1,"model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"Got it.","refusal":null,"annotations":[]},"logprobs":null,"finish_reason":"stop"}],"usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12,"prompt_tokens_details":{},"completion_tokens_details":{}},"system_fingerprint":null}')
eq(oa_full.choices[1].message.content, "Got it.", "full openai body")
eq(oa_full.choices[1].message.refusal, json.null, "openai refusal is the null sentinel")
local an_full = json.decode('{"id":"msg_1","type":"message","role":"assistant","model":"m","content":[{"type":"text","text":"Got it."}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":9,"output_tokens":3}}')
eq(an_full.content[1].text, "Got it.", "full anthropic body")
eq(next(json.decode("{}")), nil, "empty object")
eq(#json.decode("[]"), 0, "empty array")

-- Paths no other assertion reaches (from Task 3's review)
eq(json.decode("1e-05"), 1e-05, "negative exponent")
eq(json.decode('"a\\/b"'), "a/b", "escaped solidus")
eq((json.decode('{"a":1}\r\n')).a, 1, "CRLF around a body")
eq(select(1, json.decode('"\\ud800\\u0041"')), nil, "high surrogate before a non-low escape rejected")

-- Task 2's escape, round-tripped over every byte its class rewrites: the control
-- bytes, DEL, and the two JSON metacharacters. Added from Task 2's review --
-- Task 2's own test never reaches this path.
for b = 0, 127 do
  if b < 32 or b == 127 or b == 34 or b == 92 then
    local s = "a" .. string.char(b) .. "b"
    eq(json.decode(json.escape(s)), s, ("round trip of byte %d"):format(b))
  end
end
-- Acceptance item 2, malformed input: nil plus a message, never a silent drop
-- and never a raise. The plan's parse_number let tonumber() return a bare nil,
-- so "1e" came back without a message and "[1e]" parsed as an empty array.
for _, bad in ipairs({ "1e", "1e+", "1.", "-", "[1e]", '{"a":1e}', "[1.]", '{"a":-}' }) do
  local v, e = json.decode(bad)
  eq(v, nil, "malformed number rejected: " .. bad)
  eq(type(e), "string", "malformed number carries a message: " .. bad)
end
-- a million levels overflowed the Lua stack in the plan's recursive parser
local deep = string.rep("[", 1000000) .. string.rep("]", 1000000)
local ok, dv, de = pcall(json.decode, deep)
eq(ok, true, "deep nesting does not raise")
eq(dv, nil, "deep nesting is refused")
eq(type(de), "string", "deep nesting carries a message")
eq((json.decode(string.rep("[", 64) .. "7" .. string.rep("]", 64))) ~= nil, true, "ordinary depth still parses")

print(("test_json_decode: %d assertions OK"):format(n))
