package.path = package.path .. ";rime/lua/?.lua"
-- The constants are pinned to literals: a mistyped constant would otherwise
-- pass every test that reads it (feature 001, Task 8's lesson).
local keys = require("ime_translate.keys")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

eq(keys.RETURN, 0xFF0D, "Return is 0xFF0D (spike: keycode 65293)")
eq(keys.KP_ENTER, 0xFF8D, "keypad Enter is XK_KP_Enter")
eq(keys.ESC, 0xFF1B, "Esc is XK_Escape")
eq(keys.SPACE, 0x20, "Space is 0x20")
eq(keys.SHIFT_L, 0xFFE1, "Shift_L is 0xFFE1")
eq(keys.SHIFT_R, 0xFFE2, "Shift_R is 0xFFE2")
eq(keys.ALT_R, 0xFFEA, "Alt_R is 0xFFEA")
eq(keys.SHIFT, 0x1, "Shift is 0x1 (spike S14: mod=0x1)")
eq(keys.LOCK, 0x2, "Lock is 0x2")
eq(keys.CONTROL, 0x4, "Control is 0x4")
eq(keys.ALT, 0x8, "Alt is 0x8")
eq(keys.SUPER, 1 << 26, "Super is 1 << 26")

print(("test_keys: %d assertions OK"):format(n))
