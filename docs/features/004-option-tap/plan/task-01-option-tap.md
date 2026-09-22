# Task 1: The Right Option tap switches; `Ctrl+Shift+B` goes (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/shift_tap.lua`,
  `rime/lua/ime_translate/session.lua`, `rime/lua/ime_translate/decide.lua`,
  `rime/lua/ime_translate_processor.lua`
- Test: `tests/test_shift_tap.lua`, `tests/test_session.lua`,
  `tests/test_decide.lua`, `tests/test_processor.lua`

**Interfaces:**
- `shift_tap.observe(down, key, now, tap)`. `tap` defaults to `shift_tap.SHIFT`.
  `shift_tap.RIGHT_OPTION` is `{ codes = { [0xFFEA] = true }, chord = Shift |
  Control | Super }`.
- `session.option_down(ctx)` and `session.set_option_down(ctx, down)`. They
  have the same form as `shift_down`, under their own property,
  `ime_translate.option_down`.
- `decide` never returns `switch_backend`.

- [ ] **Step 1: Failing tests**
  - `test_shift_tap`:
    - A Right Option press (`0xFFEA`, Alt bit) and its release within 500 ms
      is a tap.
    - None of these is a tap: Left Option; a hold of 500 ms or more; another
      key in between; Shift or Control held; Command held.
    - The Shift default is unchanged.
    - The exports list gains `ALT_R`, `RIGHT_OPTION` and `SHIFT`.
  - `test_session`: `option_down` round-trips, separately from `shift_down`.
  - `test_decide`:
    - `Ctrl+Shift+B` is native: `noop` in idle, and `invalidate_and_pass` in
      result and error, in both cases and with the Lock bit.
    - The sweep drops its exemption for B.
  - `test_processor`:
    - 003's switch tests are driven by a Right Option tap, not
      `Ctrl+Shift+B`.
    - Also checked:
      - the Option press passes on
      - the release of a tap is taken
      - no switch on Left Option, a long hold, Option+letter, or
        `Ctrl+Shift+B`
      - a Shift tap and an Option tap do not disturb each other

- [ ] **Step 2: Run and confirm they fail**, where the old code lacks each
  piece.

- [ ] **Step 3: Implement**
  - `shift_tap.lua`: take the descriptor, as in the Interfaces above.
  - `session.lua`: a shared reader and writer for the `keycode@ms` form.
  - `decide.lua`: remove `KEY_B` and the `switch_backend` branch.
  - `processor`:
    - Move 003's switch branch into a local function, `switch_backend(S, ctx,
      draft)`, unchanged: void, `S.switch()`, notice on and off, log.
    - Observe the Right Option tap next to the Shift tap, before any early
      return.
    - After the Shift tap's block, a Right Option tap returns
      `switch_backend(...)`.

- [ ] **Step 4: Run `scripts/run_tests.sh`**: every file passes.

- [ ] **Step 5: Commit** `feat: a Right Option tap switches the backend`
