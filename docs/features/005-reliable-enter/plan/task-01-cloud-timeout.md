# Task 1: `cloud_timeout_ms` capped at 2000 (TDD)

**Files:** modify `rime/lua/ime_translate/config.lua`; test
`tests/test_config.lua`.

**Why.** backend.md §8.2: the fallback runs after the cloud fails, and a
timeout spends the cloud's whole budget. 2000 + 500 keeps the freeze at 2500.

- [ ] **Step 1: Failing tests**
  - `cloud_timeout_ms: 2500` loads as 2000, with a warning naming
    `cloud_timeout_ms` and 2000.
  - `cloud_timeout_ms: 2000` loads as 2000 with no warning.
  - `cloud_timeout_ms: 400` still resets to the default, 1500.
  - `timeout_ms: 2500` is still 2500: the local cap is unchanged.
  - Existing tests that expect a cloud cap of 2500 change to 2000.
- [ ] **Step 2: Run and confirm they fail.**
- [ ] **Step 3: Implement.** `bound_timeout` takes the ceiling; the cloud slot
  passes 2000.
- [ ] **Step 4: `scripts/run_tests.sh`** passes every file.
- [ ] **Step 5: Commit** `feat: cloud_timeout_ms capped at 2000`
