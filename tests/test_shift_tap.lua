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
eq(select(2, tap.observe({ code = L }, release(L), 10)), true, "a press stored without a time still taps")

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

-- both Shifts at once. Squirrel sends a Shift event only when the Shift flag
-- changes (upstream F21), so the second press and the first of two releases
-- never reach Rime. L down, R down, R up, L up arrives as a lone left tap,
-- covered above. L down, R down, L up, R up arrives as a left press and a right
-- release: not a tap here, although ascii_composer, which does not compare
-- keycodes, toggles on it.
t = run({ release(L) })
eq(t[1], false, "a release alone is not a tap")
t = run({ press(L), release(R) })
eq(t[2], false, "releasing the other Shift, as a two-Shift roll arrives, is not a tap")
-- a second press while a Shift is down: Squirrel never sends this stream, and
-- the rule keeps observe defined for it
t = run({ press(L), press(R), release(L) })
eq(t[3], false, "a press while a Shift is down cancels the tap")

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
eq(table.concat(names, ","), "ALT_R,RIGHT_OPTION,SHIFT,SHIFT_L,SHIFT_R,WINDOW_MS,observe",
   "exports the constants, the two tap descriptors and observe")

---------- feature 004 (design §5.6): a lone Right Option tap ----------
-- Squirrel's form (F21, F30): the press carries the Alt bit, the release only
-- the release bit. Left Option is 0xFFE9.
local ALT_R, ALT_L = 0xFFEA, 0xFFE9
eq(tap.ALT_R, ALT_R, "Alt_R is 0xFFEA")
local RO = tap.RIGHT_OPTION
local function orun(keys, times)
  local down, out = nil, {}
  for i, key in ipairs(keys) do
    local t
    down, t = tap.observe(down, key, times and times[i] or (i - 1) * 10, RO)
    out[#out + 1] = t and "T" or "-"
  end
  return table.concat(out), down
end
eq(orun({ k(ALT_R, ALT), k(ALT_R, REL, true) }), "-T", "a Right Option press and release: a tap")
eq(orun({ k(ALT_R, ALT | LOCK), k(ALT_R, LOCK | REL, true) }), "-T", "with Caps Lock on: still a tap")
eq(orun({ k(ALT_R, ALT), k(ALT_R, REL, true) }, { 0, 499 }), "-T", "released at 499 ms: a tap")
eq(orun({ k(ALT_R, ALT), k(ALT_R, REL, true) }, { 0, 500 }), "--", "released at 500 ms: a hold, not a tap")
eq(orun({ k(ALT_L, ALT), k(ALT_L, REL, true) }), "--", "Left Option is not the switch")
eq(orun({ k(ALT_R, ALT), k(A, ALT), k(ALT_R, REL, true) }), "---", "Option+letter is a chord")
eq(orun({ k(ALT_R, ALT), k(L, ALT | SHIFT), k(ALT_R, SHIFT | REL, true) }), "---", "Option with Shift is a chord")
eq(orun({ k(ALT_R, ALT | SHIFT), k(ALT_R, SHIFT | REL, true) }), "--", "Option with Shift held is a chord")
eq(orun({ k(ALT_R, ALT | CTRL), k(ALT_R, CTRL | REL, true) }), "--", "Option with Control held is a chord")
eq(orun({ k(ALT_R, ALT | SUPER), k(ALT_R, SUPER | REL, true) }), "--", "Option with Command held is a chord")
local _, od = orun({ k(ALT_R, ALT) })
assert(od and od.code == ALT_R, "a press is remembered as down")
-- the Shift default is untouched by the descriptor: a Shift tap is still a
-- tap with no descriptor, and is not a Right Option tap
local d1 = tap.observe(nil, press(L), 0)
local _, t1 = tap.observe(d1, release(L), 10)
eq(t1, true, "a Shift tap with no descriptor is still a tap")
eq(orun({ press(L), release(L) }), "--", "a Shift tap is not a Right Option tap")
local d2 = tap.observe(nil, k(ALT_R, ALT), 0)
eq(d2, nil, "Right Option is not a Shift tap")
print(("test_shift_tap: %d assertions OK"):format(n))
