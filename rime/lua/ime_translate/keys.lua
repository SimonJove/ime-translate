-- Keysyms and modifier bits, as librime receives them from Squirrel. Constants
-- only: every module that reads a key takes its numbers from here, so two
-- modules cannot drift apart on one of them.
local M = {}

-- Keysyms. XK_KP_Enter counts as Enter (decide.lua says why).
M.RETURN, M.KP_ENTER, M.ESC, M.SPACE = 0xFF0D, 0xFF8D, 0xFF1B, 0x20
-- The tap keys (shift_tap.lua). Left Option, 0xFFE9, is deliberately absent.
M.SHIFT_L, M.SHIFT_R, M.ALT_R = 0xFFE1, 0xFFE2, 0xFFEA

-- Modifier bits. Squirrel sets Lock on every key while Caps Lock is on (F12).
M.SHIFT, M.LOCK, M.CONTROL, M.ALT, M.SUPER = 0x1, 0x2, 0x4, 0x8, 0x4000000

return M
