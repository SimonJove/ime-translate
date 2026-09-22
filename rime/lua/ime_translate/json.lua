-- A pure-Lua JSON subset: escape/shq for encoding, decode for parsing (Task 3).
local M = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
                  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

function M.escape(s)
  -- An explicit byte class, not %c: %c is C's iscntrl(), which under a UTF-8
  -- ctype on macOS also matches 0x80-0x9F and 0xAD -- UTF-8 continuation bytes
  -- in most Chinese text. librime-lua shares one Lua state, so one script's
  -- os.setlocale would otherwise corrupt every sentence sent to the backend.
  local out = s:gsub('[\0-\31\127"\\]', function(c)
    return escapes[c] or ("\\u%04X"):format(string.byte(c))
  end)
  return '"' .. out .. '"'
end

-- POSIX single-quote safety: it's -> 'it'\''s'
-- The project's only shell-escaping entry point. Never use
-- string.format("%q", ...) -- that is Lua literal escaping, it produces double
-- quotes, and $() and backticks still expand inside them in a shell.
function M.shq(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

M.null = {} -- the one sentinel representing JSON null

-- Nesting ceiling for decode. The parser is recursive; a million nested brackets
-- overflowed the Lua stack and raised. Backend responses nest a handful deep.
local MAX_DEPTH = 200

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
  -- JSON's number grammar, part by part: a fraction needs digits after the dot
  -- and an exponent needs digits after the e. A single optional-everything
  -- pattern matched "1e" and "1.", and tonumber("1e") is a bare nil -- which
  -- came back without a message, and inside a container was silently dropped.
  local function parse_number()
    local p = pos
    local int = s:match("^-?%d+", p)
    if not int then return nil, err("bad number") end
    p = p + #int
    local frac = s:match("^%.%d+", p); if frac then p = p + #frac end
    local exp = s:match("^[eE][+-]?%d+", p); if exp then p = p + #exp end
    local v = tonumber(s:sub(pos, p - 1))
    if v == nil then return nil, err("bad number") end
    pos = p
    return v
  end
  parse = function(depth)
    if depth > MAX_DEPTH then return nil, err("too deep") end
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
        -- fail closed: a value-less nil refuses the document, never drops the member
        local v, e2 = parse(depth + 1); if v == nil then return nil, e2 or err("no value") end
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
        local v, e = parse(depth + 1); if v == nil then return nil, e or err("no value") end
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
  local v, e = parse(0)
  if v == nil then return nil, e end
  skip()
  if pos <= #s then return nil, ("trailing at %d"):format(pos) end
  return v
end

return M
