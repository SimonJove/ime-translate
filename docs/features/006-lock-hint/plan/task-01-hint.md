# Task 1: The hint, shown by the lock, cleared by the next key press (TDD)

**Files:** modify `rime/lua/ime_translate/state.lua`,
`rime/lua/ime_translate_processor.lua`; test `tests/test_state.lua`,
`tests/test_processor_mixed.lua`.

**Interfaces.** `state.LOCK_HINT` is `"  [en]"`. The `lock_literal` action
writes it to the last segment's prompt after confirming. Before anything
else, a key press (not a release) clears a last-segment prompt equal to it.

- [ ] **Step 1: Failing tests**
  - `test_state`: `LOCK_HINT`, and the exports list gains it.
  - `test_processor_mixed`:
    - after Enter locks, the last segment's prompt is the hint; nothing
      committed;
    - the Enter's release leaves it;
    - the next letter clears it before passing on;
    - Enter right after the lock translates, and the prompt is the
      translation;
    - a translation's prompt is not cleared by a key press that is not a
      catch-all (e.g. a Shift press).
- [ ] **Step 2: Run and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: `scripts/run_tests.sh`** passes every file.
- [ ] **Step 5: Commit** `feat: a hint when Enter locks letters`
