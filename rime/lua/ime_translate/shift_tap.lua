-- Pure: tells a lone Shift tap from Shift used as a modifier (design §5.5),
-- and, with the Right Option descriptor, a lone Right Option tap (feature 004,
-- design §5.6). A tap is a press, then its release less than 500 ms later with
-- no other key in between; for Shift either Shift counts. That is
-- ascii_composer's rule (upstream F18), except that the release must be of the
-- key that was pressed. The caller keeps `down` between keys, in Context -- a
-- module variable would be shared by every input box (design §6.1) -- and
-- passes the clock, rime_api.get_time_ms() (upstream F22).
local keys = require("ime_translate.keys")
local M = {}

M.WINDOW_MS = 500

local SHIFT, CONTROL, ALT, SUPER = keys.SHIFT, keys.CONTROL, keys.ALT, keys.SUPER
-- A tap descriptor: the keysyms that count, the modifier bits that make a
-- press or release a chord, and prop, where session keeps its `down`. A key's own bit is not a chord bit: Squirrel's
-- press carries the mask after the change (F21, F30), so Right Option's press
-- has the Alt bit. Lock is never a chord bit, since Squirrel sets it on every
-- key while Caps Lock is on.
M.SHIFT = { codes = { [keys.SHIFT_L] = true, [keys.SHIFT_R] = true },
            chord = CONTROL | ALT | SUPER, prop = "shift_down" }
-- Feature 004: the backend switch. Left Option (0xFFE9) is not it.
M.RIGHT_OPTION = { codes = { [keys.ALT_R] = true }, chord = SHIFT | CONTROL | SUPER,
                   prop = "option_down" }

-- observe(down, key, now, tap) -> down', tapped
--   down  nil, or { code = keycode, at = ms } for the key pressed alone
--   now   the clock in ms, or nil with no clock: then any hold counts
--   tap   a descriptor above; M.SHIFT when left out
function M.observe(down, key, now, tap)
  tap = tap or M.SHIFT
  local code = key.keycode
  if not tap.codes[code] then return nil, false end
  if key.modifier & tap.chord ~= 0 then return nil, false end
  if not key.release then
    if down == nil then return { code = code, at = now }, false end
    return nil, false                        -- the other Shift too: a chord
  end
  if down == nil or down.code ~= code then return nil, false end
  if now == nil or down.at == nil then return nil, true end
  return nil, now - down.at < M.WINDOW_MS
end

return M
