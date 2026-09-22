# Task 1: Shift tap recognition (TDD)

**Files:**
- Create: `rime/lua/ime_translate/shift_tap.lua`
- Test: `tests/test_shift_tap.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `shift_tap.observe(down, key, now) -> down', tapped`
    - `down`: `nil`, or `{ code = keycode, at = ms }` for a Shift pressed
      alone and not yet released. `at` is `nil` when there was no clock.
    - `key`: `{ keycode = int, modifier = int, release = bool }`, the same
      table the processor builds for `decide`
    - `now`: the clock in milliseconds, or `nil` with no clock
    - returns the new `down`, and `true` exactly when this key is the release
      of a lone tap
  - `shift_tap.SHIFT_L = 0xFFE1`, `shift_tap.SHIFT_R = 0xFFE2`,
    `shift_tap.WINDOW_MS = 500`
- The module keeps no state and reads no clock. The caller stores `down` in
  Context and passes `now` from `rime_api.get_time_ms()` (Task 4). A
  module-level variable would be shared across input boxes (design §6.1).

A lone tap is a Shift press, then its release, with no other key in between
and less than 500 ms apart. That is `ascii_composer`'s own rule (upstream F18).
- Either Shift counts; the user chose to have Right Shift behave like Left.
- Shift together with Control, Alt or Super is a chord, never a tap.
- The Lock bit (Caps Lock) is ignored, because Squirrel sets it on every key.
- Squirrel sends the press with the Shift bit and the release without it. The
  release carries only the release bit (upstream F21). The Shift bit is ignored
  either way.
- With no clock, any hold counts. That is the fallback for a librime-lua
  without `get_time_ms`.

- [ ] **Step 1: Write the failing test**

`tests/test_shift_tap.lua`:

```lua
package.path = package.path .. ";rime/lua/?.lua"
local tap = require("ime_translate.shift_tap")
local n = 0
local function eq(a, b, msg)
  n = n + 1
  assert(a == b, ("#%d %s: got %q want %q"):format(n, msg, tostring(a), tostring(b)))
end

-- literals, not the module's own constants (Task 8's lesson in feature 001)
local L, R, RET, A = 0xFFE1, 0xFFE2, 0xFF0D, string.byte("a")
local SHIFT, LOCK, CTRL, ALT, SUPER, REL = 0x1, 0x2, 0x4, 0x8, 1 << 26, 1 << 30
eq(tap.SHIFT_L, L, "Shift_L is 0xFFE1")
eq(tap.SHIFT_R, R, "Shift_R is 0xFFE2")
eq(tap.WINDOW_MS, 500, "the window is ascii_composer's 500 ms")
local function k(code, mod, rel) return { keycode = code, modifier = mod or 0, release = rel or false } end
-- Squirrel's form (upstream F21): the press carries the Shift bit, the release
-- only the release bit
local function press(code) return k(code, SHIFT) end
local function release(code) return k(code, REL, true) end

-- Run keys from no state: the first at 0 ms, each 10 ms after the one before,
-- unless `times` gives them; `times == false` runs with no clock. Returns the
-- tapped flags and the final state.
local function run(keys, times)
  local down, out = nil, {}
  for i, key in ipairs(keys) do
    local now
    if times ~= false then now = times and times[i] or (i - 1) * 10 end
    local t
    down, t = tap.observe(down, key, now)
    out[#out + 1] = t
  end
  return out, down
end

-- a lone tap, either side
local t = run({ press(L), release(L) })
eq(t[1], false, "left press is not yet a tap")
eq(t[2], true, "left release after a lone press is a tap")
t = run({ press(R), release(R) })
eq(t[2], true, "right Shift taps too")
t = run({ press(L), k(L, SHIFT | REL, true) })
eq(t[2], true, "a release that still carries the Shift bit")

-- Caps Lock on: the Lock bit changes nothing
t = run({ k(L, SHIFT | LOCK), k(L, LOCK | REL, true) })
eq(t[2], true, "a tap with the Lock bit set")

-- the window: released less than 500 ms after the press (F18)
t = run({ press(L), release(L) }, { 1000, 1499 })
eq(t[2], true, "released after 499 ms: a tap")
t = run({ press(L), release(L) }, { 1000, 1500 })
eq(t[2], false, "released after 500 ms: held, not a tap")
t = run({ press(L), release(L) }, false)
eq(t[2], true, "with no clock, any hold counts")

-- any key in between makes it a modifier, not a tap
t = run({ press(L), k(RET, SHIFT), release(L) })
eq(t[3], false, "Shift+Enter is not a tap")
t = run({ press(L), k(A, SHIFT), k(A, SHIFT | REL, true), release(L) })
eq(t[4], false, "Shift+a is not a tap")

-- chords with other modifiers are never taps
t = run({ k(L, SHIFT | CTRL), k(L, CTRL | REL, true) })
eq(t[2], false, "Control+Shift is not a tap")
t = run({ k(L, SHIFT | ALT), k(L, ALT | REL, true) })
eq(t[2], false, "Alt+Shift is not a tap")
t = run({ k(L, SHIFT | SUPER), k(L, SUPER | REL, true) })
eq(t[2], false, "Command+Shift is not a tap")

-- both Shifts down together: a chord
t = run({ press(L), press(R), release(R), release(L) })
eq(t[3], false, "second Shift release is not a tap")
eq(t[4], false, "first Shift release after both is not a tap")

-- a release with no press before it, or of the other Shift
t = run({ release(L) })
eq(t[1], false, "a release alone is not a tap")
t = run({ press(L), release(R) })
eq(t[2], false, "releasing the other Shift is not a tap")

-- state: nothing is left pending after a tap or a cancelled one
local _, down = run({ press(L), release(L) })
eq(down, nil, "no state after a tap")
_, down = run({ press(L), k(A) })
eq(down, nil, "no state after a cancelled tap")
_, down = run({ press(L) }, { 1234 })
eq(down and down.code, L, "a pending press is remembered by its keycode")
eq(down and down.at, 1234, "and by the time it went down")

-- two taps in a row are two taps
t = run({ press(L), release(L), press(L), release(L) })
eq(t[2], true, "first of two taps")
eq(t[4], true, "second of two taps")

-- purity: neither the key nor the state passed in is written, and the module
-- holds no state
local key, st = press(L), { code = L, at = 5 }
tap.observe(nil, key, 0)
tap.observe(st, release(L), 10)
eq(key.keycode .. "/" .. key.modifier .. "/" .. tostring(key.release), L .. "/1/false", "the key is untouched")
eq(st.code .. "/" .. st.at, L .. "/5", "the state passed in is untouched")
local names = {}
for name in pairs(tap) do names[#names + 1] = name end
table.sort(names)
eq(table.concat(names, ","), "SHIFT_L,SHIFT_R,WINDOW_MS,observe", "exports only the constants and observe")
print(("test_shift_tap: %d assertions OK"):format(n))
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_shift_tap.lua`
Expected: FAIL, `module 'ime_translate.shift_tap' not found`

- [ ] **Step 3: Implement**

`rime/lua/ime_translate/shift_tap.lua`:

```lua
-- Pure: tells a lone Shift tap from Shift used as a modifier (design §5.5).
-- A tap is a Shift press, then its release less than 500 ms later with no
-- other key in between; either Shift counts. That is ascii_composer's own
-- rule (upstream F18). The caller keeps `down` between keys, in Context -- a
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
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_shift_tap.lua && scripts/run_tests.sh`
Expected: `test_shift_tap: 29 assertions OK`, and every file PASS.

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/shift_tap.lua tests/test_shift_tap.lua
git commit -m "feat: recognize a lone Shift tap, pure and stateless"
```
