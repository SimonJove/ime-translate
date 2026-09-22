# Task 3: JSON decoding (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/json.lua`
- Test: `tests/test_json_decode.lua`

**Interfaces:**
- Consumes: Task 2's module skeleton
- Produces: `json.decode(s) -> value, err` — returns `nil, errmsg` on failure;
  supports object / array / string / number / bool / null / nesting, `\uXXXX`
  (including surrogate pairs) and raw UTF-8. `json.null` is the one sentinel
  representing JSON null.

- [ ] **Step 1: Write the failing test**

`tests/test_json_decode.lua`:

```lua
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

-- Task 2's escape, round-tripped over every byte its class rewrites: the control
-- bytes, DEL, and the two JSON metacharacters. Added from Task 2's review --
-- Task 2's own test never reaches this path.
for b = 0, 127 do
  if b < 32 or b == 127 or b == 34 or b == 92 then
    local s = "a" .. string.char(b) .. "b"
    eq(json.decode(json.escape(s)), s, ("round trip of byte %d"):format(b))
  end
end
print(("test_json_decode: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_json_decode.lua`
Expected: FAIL (`decode is nil` — not implemented yet)

- [ ] **Step 3: Implement decode**

Append before `return M` in `rime/lua/ime_translate/json.lua`:

```lua
M.null = {} -- the one sentinel representing JSON null

local function utf8_enc(cp) -- code point -> UTF-8 bytes
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
  elseif cp < 0x10000 then return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
  else return string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
  end
end

function M.decode(s)
  local pos = 1
  -- err returns only a message string. If it returned (nil, msg), a caller's
  -- `return nil, err(...)` would expand to three values (nil, nil, msg) and the
  -- error message would be lost at `local k, e = parse_string()`.
  local function err(m) return ("%s at %d"):format(m, pos) end
  local function skip() while pos <= #s and s:find("^[ \t\r\n]", pos) do pos = pos + 1 end end
  local parse -- forward declaration
  local function parse_string()
    if s:byte(pos) ~= 0x22 then return nil, err("not string") end
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then return nil, err("unterminated") end
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        pos = pos + 2
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[e] then out[#out + 1] = map[e]
        elseif e == "u" then
          local hex = s:sub(pos, pos + 3)
          if not hex:match("^%x%x%x%x$") then return nil, err("bad \\u") end
          pos = pos + 4
          local cp = tonumber(hex, 16)
          if cp >= 0xD800 and cp <= 0xDBFF then -- high surrogate: expect \uDC00-\uDFFF next
            if s:sub(pos, pos + 1) ~= "\\u" then return nil, err("lone surrogate") end
            local hex2 = s:sub(pos + 2, pos + 5)
            if not hex2:match("^%x%x%x%x$") then return nil, err("bad \\u low") end
            local lo = tonumber(hex2, 16)
            if lo < 0xDC00 or lo > 0xDFFF then return nil, err("bad low surrogate") end
            pos = pos + 6
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
          elseif cp >= 0xDC00 and cp <= 0xDFFF then return nil, err("unexpected low surrogate") end
          out[#out + 1] = utf8_enc(cp)
        else return nil, err("bad escape") end
      else
        out[#out + 1] = c; pos = pos + 1
      end
    end
  end
  local function parse_number()
    local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not num then return nil, err("bad number") end
    pos = pos + #num
    return tonumber(num)
  end
  parse = function()
    skip()
    if pos > #s then return nil, err("eof") end
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1; local t = {}
      skip()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        skip()
        local k, e = parse_string(); if not k then return nil, e end
        skip()
        if s:sub(pos, pos) ~= ":" then return nil, err("expect :") end
        pos = pos + 1
        local v, e2 = parse(); if v == nil and e2 then return nil, e2 end
        t[k] = v
        skip()
        local sep = s:sub(pos, pos)
        if sep == "," then pos = pos + 1
        elseif sep == "}" then pos = pos + 1; return t
        else return nil, err("expect , or }") end
      end
    elseif c == "[" then
      pos = pos + 1; local a = {}
      skip()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return a end
      while true do
        local v, e = parse(); if v == nil and e then return nil, e end
        a[#a + 1] = v
        skip()
        local sep = s:sub(pos, pos)
        if sep == "," then pos = pos + 1
        elseif sep == "]" then pos = pos + 1; return a
        else return nil, err("expect , or ]") end
      end
    elseif c == '"' then return parse_string()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return M.null
    else return parse_number() end
  end
  local v, e = parse()
  if v == nil then return nil, e end
  skip()
  if pos <= #s then return nil, ("trailing at %d"):format(pos) end
  return v
end
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `lua tests/test_json_decode.lua && lua tests/test_json_encode.lua`
Expected: both files OK

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/json.lua tests/test_json_decode.lua
git commit -m "feat: JSON decoding with surrogate pairs and three response shapes"
```
