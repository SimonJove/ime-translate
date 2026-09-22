# Task 2: Enter on a draft with no Chinese (TDD)

**Files:**
- Modify: `rime/lua/ime_translate/decide.lua` (the `decide` signature and its
  Enter branch)
- Test: `tests/test_decide.lua` (append before the final `print`)

**Interfaces:**
- Consumes: `state.IDLE/RESULT/ERROR` (001, Task 4).
- Produces:
  - `decide.decide(key, phase, draft_empty, draft_ascii)`
  - `draft_ascii` is `true` when the draft holds no byte ≥ 0x80, that is no
    Chinese character and no full-width mark. Omitted or `false`, behaviour is
    exactly as before, so every existing caller and test is unchanged.
- The processor passes it in Task 4.

Design §5.5, which is the user's decision: Enter in `idle` on a non-empty draft
with no Chinese commits it as is, with no backend call. In `result` and `error`
nothing changes.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_decide.lua`, just before its final `print(...)`:

```lua
---------- feature 002 (design §5.5): a draft with no Chinese ----------
local function is4(key, phase, empty, ascii, want, msg)
  n = n + 1
  local got = decide.decide(key, phase, empty, ascii).type
  assert(got == want, ("#%d %s: got %q want %q"):format(n, msg, got, want))
end
is4(k(RET), state.IDLE, false, true, "commit_draft", "enter, ascii draft: commit as is")
is4(k(KP_ENTER), state.IDLE, false, true, "commit_draft", "keypad enter, ascii draft")
is4(k(RET, LOCK), state.IDLE, false, true, "commit_draft", "enter+lock, ascii draft")
is4(k(RET), state.IDLE, false, false, "translate", "enter, draft with Chinese: translate")
is4(k(RET), state.IDLE, false, nil, "translate", "no flag: as before")
is4(k(RET), state.IDLE, true, true, "noop", "empty draft stays native")
is4(k(RET), state.RESULT, false, true, "commit_translation", "result is unchanged")
is4(k(RET), state.ERROR, false, true, "commit_draft", "error is unchanged")
is4(k(RET, SHIFT), state.IDLE, false, true, "commit_draft", "shift-enter is unchanged")
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `lua tests/test_decide.lua`
Expected: FAIL at the first new assertion,
`enter, ascii draft: commit as is: got "translate" want "commit_draft"`

- [ ] **Step 3: Implement**

In `rime/lua/ime_translate/decide.lua`, change the comment line for
`commit_draft` and the function head:

```lua
--   commit_draft         the processor commits the Chinese draft -- skip, fall
--                        back, or a draft with no Chinese (design §5.5)
```

```lua
function M.decide(key, phase, draft_empty, draft_ascii)
```

and in the plain-Enter branch, add one line before `return { type = "translate" }`:

```lua
  if enter and mods == 0 then
    if draft_empty then return { type = "noop" } end
    if phase == state.RESULT then return { type = "commit_translation" } end
    if phase == state.ERROR then return { type = "commit_draft" } end
    -- design §5.5: a draft with no Chinese has nothing to translate
    if draft_ascii then return { type = "commit_draft" } end
    return { type = "translate" }
  end
```

- [ ] **Step 4: Run it and confirm it passes**

Run: `lua tests/test_decide.lua && scripts/run_tests.sh`
Expected: `test_decide: 69 assertions OK`, and every file PASS.

- [ ] **Step 5: Commit**

```bash
git add rime/lua/ime_translate/decide.lua tests/test_decide.lua
git commit -m "feat: Enter commits a draft with no Chinese as is"
```
