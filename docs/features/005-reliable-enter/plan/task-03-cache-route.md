# Task 3: The cache and the route, with the cloud-to-local fallback (TDD)

**Files:** create `rime/lua/ime_translate/cache.lua`,
`rime/lua/ime_translate/route.lua`; modify
`rime/lua/ime_translate_shared.lua`; test `tests/test_cache.lua`,
`tests/test_route.lua`, `tests/test_shared.lua`.

**Interfaces.**
- `cache.new(n)` → an object with `get(slot, draft)` → text or `nil`, and
  `put(slot, draft, text)`. It holds the `n` most recently put or read
  entries; the oldest goes first.
- `route.translate(S, draft, runner)` → `{ ok, text, code, cloud, fallback }`.
  `S` is the shared singleton: `S.active`, `S.current()`, `S.settings`,
  `S.api_key`, `S.cache`.
  1. The slot is `cloud` when `S.current()` returns the cloud slot, else
     `local`. A cache hit for the slot and draft returns at once.
  2. Otherwise `backend.translate` with the slot's settings and key. Success
     is cached and returned.
  3. A failure of the `local` slot, or `too_long`, returns the error.
  4. A failure of the `cloud` slot tries the local slot: a cache hit, or
     `backend.translate` with the local settings, `timeout_ms` = 500
     (`route.FALLBACK_MS`), and the local key. Success is cached under
     `local` and returned with `fallback = true`; failure returns the
     cloud's error.
  - `cloud` is whether the settings that answered have a non-loopback
    `base_url`.
- `shared.ensure()` creates `shared.cache = cache.new(32)` once.

- [ ] **Step 1: Failing tests**
  - `cache`: get after put; a miss; the slot is part of the key; the 33rd put
    evicts the least recent; a get refreshes an entry.
  - `route`, with a counting fake runner:
    - local success: one request, then a second call is a cache hit with no
      request;
    - local failure: the error, no second request, nothing cached;
    - cloud success: `cloud = true`, `fallback = false`;
    - cloud timeout then local success: `fallback = true`, `cloud = false`,
      the second request's `--max-time` is `0.500`;
    - cloud failure then local failure: the cloud's code;
    - cloud `too_long`: no local request;
    - errors are never cached: the same draft after an error asks again.
  - `shared`: `ensure` creates the cache once.
- [ ] **Step 2: Run and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: `scripts/run_tests.sh`** passes every file.
- [ ] **Step 5: Commit** `feat: the cloud falls back to local; a translation cache`
