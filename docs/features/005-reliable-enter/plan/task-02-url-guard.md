# Task 2: The URL guard in the `libretranslate` adapter (TDD)

**Files:** modify `rime/lua/ime_translate/backend.lua`,
`rime/lua/ime_translate/state.lua`; test `tests/test_backend.lua`,
`tests/test_state.lua`.

**Interfaces.**
- `backend.guard(text)` → `sent, urls`. Each `http://` or `https://` URL (a run
  of URL characters, less trailing `.,;:!?'"`) becomes `X_1`, `X_2`, … in
  order; `urls` lists them. With no URL, or a text already holding `X_<digit>`,
  it returns `text, nil`.
- `backend.unguard(out, urls)` → the output with each `X_n` put back, or `nil`
  when any `X_n` does not occur exactly once.
- An adapter may define `prepare(text)` → `sent, state` and
  `finish(out, state)` → `out` or `nil`. Only `libretranslate` does.
  `translate` returns `false, "bad_guard"` when `finish` returns `nil`.
- `state.error_message("bad_guard")` is `✗ 翻译失败`.

- [ ] **Step 1: Failing tests**
  - `guard`: one URL; two URLs; a URL glued to Chinese on both sides; trailing
    punctuation left outside; no URL; a text already holding `X_1`.
  - `unguard`: restores; a missing placeholder is `nil`; a doubled one is
    `nil`; `X_1` inside `X_12` is not mistaken for it.
  - `translate` with the `libretranslate` adapter and a fake runner: the
    request body carries `X_1`, not the URL; the result carries the URL; a
    runner that drops `X_1` gives `false, "bad_guard"`.
  - The `openai` and `anthropic` bodies still carry the URL as typed.
- [ ] **Step 2: Run and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: `scripts/run_tests.sh`** passes every file.
- [ ] **Step 5: Commit** `feat: translate keeps URLs through placeholders`
