# Task 4: Enter retries in `error`; the processor uses the route (TDD)

**Files:** modify `rime/lua/ime_translate/decide.lua`,
`rime/lua/ime_translate/session.lua`,
`rime/lua/ime_translate_processor.lua`; test `tests/test_decide.lua`,
`tests/test_session.lua`, `tests/test_processor.lua`.

**Interfaces.**
- `decide`: Enter with no modifier in `error` → `translate`.
- `session.set_result(ctx, draft, text, cloud, fallback)`; a new property
  `ime_translate.fallback`; `clear` resets it; `session.prompt` shows
  `  ☁✗ -> text` for a loopback fallback and `  ☁✗ ☁ text` for a non-loopback
  one.
- The processor's `translate` branch calls
  `route.translate(S, draft, backend.real_runner)`.

- [ ] **Step 1: Failing tests**
  - `decide`: Enter in `error` is `translate`, with and without the Lock bit;
    Shift+Enter in `error` is still `commit_draft`.
  - `session`: the fallback prompt; `clear` resets the flag; a plain result
    after a fallback shows `->` again.
  - `processor`, with the runner replaced:
    - error, then Enter: a second request, and the translation shows;
      nothing committed;
    - cloud active, the cloud request fails, the local one succeeds: the
      prompt is `  ☁✗ -> …`, and the next Enter commits it;
    - Esc then Enter on the same draft: no second request;
    - the caret rule still moves the caret first in `error`.
- [ ] **Step 2: Run and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: `scripts/run_tests.sh`** passes every file.
- [ ] **Step 5: Commit** `feat: Enter retries after an error; the processor routes`
