-- Pure: tells a lone Shift tap from Shift used as a modifier (design §5.5).
-- A tap is a Shift press, then its release less than 500 ms later with no
-- other key in between; either Shift counts. That is ascii_composer's rule
-- (upstream F18), except that the release must be of the Shift that was
-- pressed. The caller keeps `down` between keys, in Context -- a
-- module variable would be shared by every input box (design §6.1) -- and
-- passes the clock, rime_api.get_time_ms() (upstream F22).
local M = {}

M.SHIFT_L, M.SHIFT_R = 0xFFE1, 0xFFE2
M.WINDOW_MS = 500
-- Control, Alt, Super: Shift with any of these is a chord, never a tap. Lock
-- is ignored, since Squirrel sets it on every key while Caps Lock is on.
local CHORD = 0x4 | 0x8 | 0x4000000

-- observe(down, key, now) -> down', tapped
--   down  nil, or { code = keycode, at = ms } for a Shift pressed alone
--   now   the clock in ms, or nil with no clock: then any hold counts
function M.observe(down, key, now)
  local code = key.keycode
  if code ~= M.SHIFT_L and code ~= M.SHIFT_R then return nil, false end
  if key.modifier & CHORD ~= 0 then return nil, false end
  if not key.release then
    if down == nil then return { code = code, at = now }, false end
    return nil, false                        -- the other Shift too: a chord
  end
  if down == nil or down.code ~= code then return nil, false end
  if now == nil or down.at == nil then return nil, true end
  return nil, now - down.at < M.WINDOW_MS
end

return M
