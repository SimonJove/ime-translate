# Task 2: `Ctrl+Shift+B` in `decide` (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/decide.lua`
- Test: `tests/test_decide.lua` (append before the final `print`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `decide.decide(...)` returns `{ type = "switch_backend" }` for a
  `Ctrl+Shift+B` press, in every phase, with or without a draft. Task 4
  executes it. The signature is unchanged.

Design §5.6 and §5.2's row. Squirrel sends the letter as `B` (0x42), or as
`b` (0x62) when Shift and Caps Lock are both on (upstream F29), so both count.
The Lock bit is already dropped by `MODIFIERS`. Any other modifier set is not
the hotkey: `Ctrl+B` in `result` still voids the translation and passes, and
`Shift+B` is a capital letter.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_decide.lua`, just before its final `print(...)`:

```lua
---------- feature 003 (design §5.6): Ctrl+Shift+B switches the backend ----------
local B, LOWER_B, T = 0x42, 0x62, 0x54
for _, ph in ipairs({ state.IDLE, state.RESULT, state.ERROR }) do
  for _, empty in ipairs({ true, false }) do
    is(k(B, CTRL | SHIFT), ph, empty, "switch_backend",
       ("ctrl+shift+B, %s, draft %s"):format(ph, empty and "empty" or "open"))
  end
end
is(k(LOWER_B, CTRL | SHIFT), state.IDLE, false, "switch_backend", "lowercase b: Shift with Caps Lock on")
is(k(B, CTRL | SHIFT | LOCK), state.RESULT, false, "switch_backend", "the Lock bit is ignored")
is(k(B, CTRL | SHIFT, true), state.RESULT, false, "noop", "the release is noop")
is(k(B, CTRL), state.IDLE, false, "noop", "ctrl+B alone is not the hotkey")
is(k(B, CTRL), state.RESULT, false, "invalidate_and_pass", "ctrl+B in result voids and passes")
is(k(B, SHIFT), state.IDLE, false, "noop", "shift+B is a capital letter")
is(k(B, CTRL | SHIFT | ALT), state.IDLE, false, "noop", "with Alt it is not the hotkey")
is(k(B, CTRL | SHIFT | SUPER), state.IDLE, false, "noop", "with Command it is not the hotkey")
is(k(T, CTRL | SHIFT), state.IDLE, false, "noop", "ctrl+shift+T stays native: the schema switch")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_decide.lua`
Expected: FAIL at the first new assertion,
`ctrl+shift+B, idle, draft empty: got "noop" want "switch_backend"`.

- [ ] **Step 3: Implement**

In `rime/lua/ime_translate/decide.lua`, below `M.SPACE = 0x20`:

```lua
-- Feature 003 (design §5.6): the backend-switch hotkey is Ctrl+Shift+B. The
-- letter arrives uppercase, or lowercase with Shift and Caps Lock both on
-- (upstream F29).
M.KEY_B, M.KEY_LOWER_B = 0x42, 0x62
```

In the action list comment, after `literal_space`:

```lua
--   switch_backend       the processor switches the translation backend (§5.6)
```

In `M.decide`, right after `local enter = …`:

```lua
  -- Feature 003 (design §5.6): in every phase, with or without a draft
  if (code == M.KEY_B or code == M.KEY_LOWER_B) and mods == M.CONTROL | M.SHIFT then
    return { type = "switch_backend" }
  end
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_decide.lua && scripts/run_tests.sh`
Expected: `test_decide: … assertions OK`, and every file PASS.

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/decide.lua tests/test_decide.lua
git commit -m "feat: Ctrl+Shift+B decides to switch the backend"
```
