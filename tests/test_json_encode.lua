package.path = package.path .. ";rime/lua/?.lua"
local json = require("ime_translate.json")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

-- Two CJK characters (U+4E2D U+6587) spelled as their UTF-8 bytes, which are
-- what this passthrough test is about.
local CJK = "\228\184\173\230\150\135"

-- Run under a UTF-8 ctype when the machine has one. Lua's %c class is C's
-- iscntrl(), which under a UTF-8 locale on macOS also matches 0x80-0x9F and 0xAD
-- -- ordinary UTF-8 continuation bytes. librime-lua shares one Lua state, so any
-- script's os.setlocale reaches json.escape; the passthrough test must see that.
local UTF8_CTYPE = os.setlocale("en_US.UTF-8", "ctype") or os.setlocale("C.UTF-8", "ctype")
if not UTF8_CTYPE then
  io.stderr:write("note: no UTF-8 ctype locale here; the passthrough test ran under C\n")
end

eq(json.escape("hello"), '"hello"', "plain")
eq(json.escape('say "hi"'), '"say \\"hi\\""', "double quote")
eq(json.escape("line1\nline2"), '"line1\\nline2"', "newline")
eq(json.escape("tab\t"), '"tab\\t"', "tab")
eq(json.escape("back\\slash"), '"back\\\\slash"', "backslash")
eq(json.escape(CJK), '"' .. CJK .. '"', "raw utf8 passthrough")
eq(json.shq("plain"), "'plain'", "shq plain")
eq(json.shq("it's"), "'it'\\''s'", "shq single quote")
eq(json.shq("a$b`c"), "'a$b`c'", "shq metachars")
eq(json.shq('x"y'), "'x\"y'", "shq double quote stays literal")
print(("test_json_encode: %d assertions OK"):format(n))
