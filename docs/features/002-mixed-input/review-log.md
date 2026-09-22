# Review log

Every task is reviewed by `task-reviewer` before it is marked done; the
procedure is `.claude/skills/task-review/SKILL.md`. Any 🔴 means another round,
and **each round is appended, never overwritten**.

Documentation-only tasks are not reviewed. Task 6 is manual; its record is
`docs/smoke-report-002.md`.

---

## Task 1: Shift tap recognition — round 1

Range: `4588f6f..HEAD` holds no commit of this task. Task 1 is staged, not
committed, and was reviewed as `git diff --cached 4588f6f`: two new files,
`rime/lua/ime_translate/shift_tap.lua` and `tests/test_shift_tap.lua`. For both,
the staged content equals the working tree. Not reviewed:
`docs/features/002-mixed-input/progress.json`, which is ledger state.
Time: 2026-09-22T05:00Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_shift_tap.lua:71-74` and `rime/lua/ime_translate/shift_tap.lua:24`:
  the two-Shift chord is tested on an event stream Squirrel never sends.** The
  block feeds `press(L), press(R), release(R), release(L)` and asserts that
  neither release is a tap. Line 24's comment reads "the other Shift too: a
  chord". F21's own source says the second Shift never reaches Rime.
  - **Source reading** (Squirrel `SquirrelInputController.swift`
    `handle(_:client:)`, the `.flagsChanged` case, the function F21 cites; the
    two copies read for F21, tag 1.1.2 and master, are identical here; not
    measured). A Rime key event is sent only for a flag in
    `[.shift, .control, .option, .command]` that appears in
    `changes = lastModifiers.symmetricDifference(modifiers)`. Pressing the
    second Shift while the first is held does not change `.shift`. Either
    `lastModifiers == modifiers` and the early return fires, or only a
    device-dependent bit changed and the loop appends nothing. Releasing the
    first of two Shifts is the same.
  - **What the processor receives** (derivation from the above):
    - L down, R down, R up, L up gives a `Shift_L` press, then a `Shift_L`
      release. `observe` returns tapped = true (checked by feeding exactly that
      stream to the staged module). So "both Shifts down together: a chord"
      does not hold on the real machine. Rolling both Shifts inside 500 ms is a
      tap, and Task 4 will lock the segment and switch mode.
    - L down, R down, L up, R up gives a `Shift_L` press, then a `Shift_R`
      release. That is not a tap (line 26, #20). `ascii_composer` does toggle
      there: it keys on `shift_key_pressed_`, not on the keycode
      (`ProcessKeyEvent`, 1.16.0). So the header's "That is ascii_composer's
      own rule" (lines 3-4) is not exact for two Shifts, in either order.
  - **Even as a model, the block does not pin line 24.** Mutating it to
    `return down, false` passes 29/29. `release(R)` at #17 already clears
    `down` through the other-Shift rule before #18 runs.

  Consequence: nothing is lost, since a tap only confirms and switches
  (upstream §15.5). That is why this is yellow. But the unit suite asserts a
  behaviour the frontend contradicts, and no Task 6 row would catch it. That is
  R10's pattern (review dimension 8): a fake event stream standing in for
  Squirrel.

  Fix, the implementer's choice:
  - Rewrite the block with the streams Squirrel sends, each labelled as derived
    from F21's `.flagsChanged` source:
    - `press(L), release(L)` for the L-R-R-L roll: a tap
    - `press(L), release(R)` for L-R-L-R: not a tap

    Then say at line 24 that the branch serves a frontend that reports the
    second Shift, and is unreachable from Squirrel.
  - Or keep the chord model, but order it `press(L), press(R), release(L)` so
    that it actually pins line 24, with the same label.
  - Either way:
    - Soften "That is ascii_composer's own rule" so that it names the
      difference.
    - Consider a `/design-review` note narrowing F21's "each modifier change
      becomes one Rime key event" to "each change of a device-independent
      modifier flag".
  - A Task 6 row for the two-Shift roll would make it measured.

### 🟢 Suggestions
- **`rime/lua/ime_translate/shift_tap.lua:27`: the `down.at == nil` guard has
  no assertion of its own.** The interface allows `at = nil` on its own ("`at`
  is `nil` when there was no clock"), and Task 4's plan stores that as
  `keycode@` with an empty time. Dropping `or down.at == nil` passes 29/29,
  because #11 also passes `now = nil` and the first operand short-circuits. No
  path reaches the mixed case today. But if a `down` without `at` ever meets a
  clock (for example, a `session.shift_down` decode that yields no number),
  line 28 raises `attempt to perform arithmetic on a nil value (field 'at')`
  inside the processor. One assertion pins it:
  `select(2, tap.observe({ code = L }, release(L), 10)) == true`.

### What was walked
- **Red lines 1-5.** Not reachable from this diff. There is no `ctx:clear`, no
  `commit_text`, no shell and no Context access. `session.lua`, the processor
  and the translator are untouched. D7 (open) blocks 002 Task 5 only.
- **Purity.** `luac -l` shows no `GETTABUP` or `SETTABUP` on `_ENV`, in the
  chunk or in `observe`. `observe`'s only upvalues are `M` and the constant
  `CHORD`. There is no `os.*` and no `rime_api`.
- **The 500 ms boundary.** `ascii_composer` sets
  `toggle_expired_ = press + 500 ms` and toggles iff `now < toggle_expired_`,
  that is release − press < 500. Line 28 uses the same strict `<`, and #9/#10
  pin 499 and 500. `get_time_ms` truncates to whole milliseconds
  (`duration_cast<milliseconds>`, librime-lua `types.cc`). So the module is
  stricter than `ascii_composer` by less than 1 ms, and never looser. Not a
  finding.
- **The release.** Squirrel computes the modifier after the change, then ORs
  `kReleaseMask`, so Shift's release has no Shift bit (F21). #5 uses that form,
  and a mutant that requires the Shift bit on the release dies at #5. #7 keeps
  the older form.
- **Chords, in the real order.**
  - Control held first: the `Control_L` press resets `down`. The `Shift_L`
    press then carries the Control bit, and only `CHORD` stops it becoming a
    tap. #14-16 isolate the mask, and dropping any single bit is killed.
  - Shift held first: the `Control_L` press resets `down` (line 20).
  - Shift+Enter and Shift+letter are covered by #12-13.
- **Lock.** `osxModifiersToRime` sets `kLockMask` on every event while Caps
  Lock is on (F12). #8 covers it, and adding Lock to `CHORD` dies at #8.
- **Constants, checked literally.**
  - `0xFFE1`/`0xFFE2` = Squirrel's `kVK_Shift: XK_Shift_L` and
    `kVK_RightShift: XK_Shift_R`.
  - Control `0x4`, Alt `0x8` (`.option` → `kAltMask`), Super `1 << 26`
    (`.command` → `kSuperMask`), the same as `decide.lua`'s masks.
  - `WINDOW_MS = 500` = `toggle_duration_limit`.
- **Mutation.** 25 mutants of the module in a scratch copy, 21 killed.
  - Two survivors are equivalent: an unused local, and reading the release
    bit instead of the `release` field, which the processor derives from the
    same bit.
  - The other two are yellow 1 (line 24) and green 1 (line 27).
  - A hidden-state mutant, which keeps `down` in an upvalue and ignores the
    argument, dies at #25.
- **Deviations.** None. Both staged files are byte-identical to the plan's two
  code blocks.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_shift_tap.lua` passes every assertion | ok | `test_shift_tap: 29 assertions OK`, the plan's count. `scripts/run_tests.sh` passes every file, and `.githooks/pre-commit` exits 0 over the staged content. Step 2's red was reproduced in a sandbox without the module: `module 'ime_translate.shift_tap' not found` |
| A tap is a press and release of the same Shift less than 500 ms apart with no other key between; a chord with Control, Alt or Super, or a longer hold, is not | ok | #5-6 (either Shift), #9-10 (499/500 ms), #12-13 (a key between), #14-16 (each chord bit), #20 (the other Shift). The boundary matches `ascii_composer`'s `now < toggle_expired_`. Real two-Shift streams: yellow 1 |
| With no clock, any hold counts | ok | #11 and line 27. The mixed case (`now` set, `at` nil) is untested: green 1 |
| The module is pure: no state, no clock read, no rime global | ok | Bytecode shows no `_ENV` access. #27-28: the key and state passed in are unmutated. #29: exactly four exports. The hidden-state mutant is killed |

### Verdict
0 red / 1 yellow / 1 green: no red, clear to close. Fix yellow 1, or defer it
with a one-line reason recorded here.

---

### Author response to round 1
- **Yellow 1, fixed.** The two-Shift block now uses the streams Squirrel sends.
  - A roll ending on the other Shift arrives as `press(L), release(R)`, and it
    is not a tap.
  - A roll ending on the first Shift arrives as a lone tap, covered earlier.
  - A separate assertion, `press(L), press(R), release(L)`, is labelled as a
    stream Squirrel never sends. It pins line 24: the `return down, false`
    mutant now dies at #20.

  The module's header comment now says the rule is `ascii_composer`'s except
  that the release must be of the Shift that was pressed. F21 is narrowed, and
  Task 6 gains record row 29 for both rolls. Both are logged in decisions.md,
  "002 Task 1 review: a two-Shift roll".
- **Green 1, fixed.** `observe({ code = L }, release(L), 10)` taps. Removing the
  `down.at == nil` guard now fails with arithmetic on nil.
- **Deviation from the plan's code.** Only these test lines and the comment
  change; the module's logic is as planned. The count stays 29: the old block
  had two assertions, the new one has one, and green 1 adds one.

---

## Task 2: Enter on a draft with no Chinese — round 1

Range: `cf0fb12..HEAD` holds no commit of this task. Task 2 is staged, not
committed, and was reviewed as `git diff --cached cf0fb12`:
`rime/lua/ime_translate/decide.lua` and `tests/test_decide.lua`. For both, the
staged content equals the working tree. Not reviewed:
`docs/features/002-mixed-input/progress.json`, which is ledger state.
Time: 2026-09-22T05:12Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_decide.lua:137-154` (the catch-all sweep) and `:182-196`:
  nothing checks that `draft_ascii = true` leaves every row except plain Enter
  alone. That is the input Task 4 feeds on every key.** Task 4 passes
  `not draft:find("[\128-\255]")` on every key event. On an English draft,
  decide therefore sees `true` for each letter, BackSpace, Esc and Ctrl+Enter.
  The new block passes `true` only with Enter and Shift+Enter. The sweep and
  the purity loop pass three arguments, that is `nil`. Four one-line mutants of
  `decide.lua` each widen the rule past plain Enter, and each passes all 69
  assertions. They were run in scratch copies against the staged test:
  - **M9**: `if draft_ascii and not draft_empty and phase == state.IDLE then
    return { type = "commit_draft" } end` ahead of the Enter branch, in place of
    line 37. Once Task 4 wires the argument, a letter typed into an English
    draft commits the draft and is itself taken (`kAccepted`). Typing `Hello`
    in Chinese mode would commit `H` and lose the `e`.
  - **M10**: `if code == M.ESC and (phase ~= state.IDLE or draft_ascii)`. Esc
    on an English draft in idle is taken and never reaches the native
    `CancelComposition`, so the draft cannot be cancelled.
  - **M8**: the rule hoisted above the `mods == 0` test as `enter and …`.
    Ctrl+Enter on an English draft is taken instead of reaching
    `fluid_editor`'s `CommitRawInput`.
  - **M11**: `if phase ~= state.IDLE or draft_ascii` in the catch-all. Every key
    in idle on an English draft goes through `invalidate_and_pass`.

  Task 4's planned processor tests would not catch M9 or M10 either. Their only
  English draft presses Enter. The first place to see either mutant would be
  the real machine (Task 6 row 7).

  Fix, checked in a scratch copy:
  - In the sweep, wrap the phase loop in `for _, ascii in ipairs({ false, true
    })` and pass `ascii` as the fourth argument. That is 6.29 M calls, and the
    file takes 0.8 s instead of 0.4 s.
  - Add `is4(k(ESC), state.IDLE, false, true, "noop", "esc on an ascii draft
    stays native")`. Esc is a named row that the sweep skips.

  With both changes, M8–M11 die and the staged module passes (70 assertions).
  The `false` loop also covers the "or false" half of acceptance item 3 across
  the whole key space. Today one row (#64) covers it.

### 🟢 Suggestions
- None.

### What was walked
- **Red lines 1-5.** `decide.lua` has no `ctx:clear`, no `commit_text`, no
  Context access and no shell.
  - The new outcome goes to the existing `commit_draft` branch
    (`ime_translate_processor.lua:112-117`). That branch commits `draft` before
    `session.clear` and `ctx:clear()`, and returns `kAccepted`, so the Enter
    never reaches the application and sending stays manual.
  - Task 4's argument classifies the same `draft` string that this branch
    commits. So "no Chinese" is judged on exactly the text that gets
    committed.
  - Until Task 4, the processor passes three arguments
    (`ime_translate_processor.lua:71`), so the rule is not yet active in the
    product. `test_processor` still reports 81 OK.
- **Purity.** `luac -l -l`: `decide` takes 4 params, its only upvalues are `M`
  and `state`, and it has no `_ENV` access and no `SETTABUP`.
- **Which drafts count.** Task 4's expression was run on samples in Lua 5.4.8.
  `git status`, `Hello` and `` `zz `` give true.
  `今天`, `，`, `hello，` and `é` give false.
  `""` gives true, but `draft_empty` wins (#66). Lua patterns compare bytes
  as unsigned char, so the class is exactly the bytes 0x80–0xFF.
  - **Drafts with no Chinese that this schema can produce** (derivations):
    - an English-mode draft (F19)
    - a raw segment from the uppercase pattern in Chinese mode (Task 6 row 18)
    - a reverse lookup with no match: `` `zz `` is tagged by `matcher`, has no
      candidate, and so reads as raw input (F5)
    - an ASCII custom phrase

    In each case the committed string is what native `fluid_editor` Return
    commits. That path is `CommitComposition`, then `Context::Commit`, then
    `GetCommitText` (source reading: librime `gear/editor.cc` 119-122 and 194,
    `context.cc` 18-26, in the review cache).
  - **Non-ASCII that is not Chinese still translates.** That covers full-width
    marks, `……`, the symbols from the `/` pattern and accented Latin. This is
    the conservative direction:
    - at worst, one backend call
    - the result is shown before a second Enter commits it
    - never a loss

    The plan's interface defines it this way, so it is not a deviation.
  - **An empty commit text with a non-empty input.** It would classify as ASCII,
    so the processor would commit `""` and then clear. It is not reachable here:
    - `Context::GetCommitText` returns `""` only under `dumb`, which
      `switcher.cc` sets on the switcher's own context (source reading).
    - It also skips segments tagged `phony`. No cached gear sets that tag. It
      is believed to be `affix_segmentor`'s, which this schema does not list
      (unverified).
    - With the caret inside, the caret rule acts first. With the caret at the
      end, F5 gives every segment's candidate or its raw slice.
  - **The caret inside the input.** `draft` stops at the caret (F15), so the
    class is judged on a prefix. That does no harm:
    - `translate` and `commit_draft` are both in `ACTS_ON_DRAFT`
      (`ime_translate_processor.lua:34`).
    - So the first press only moves the caret, and the next press is judged on
      the whole draft.
    - `commit_draft` has to stay in `ACTS_ON_DRAFT`, but it already must for
      Shift+Enter.
  - **The result and error phases.** Their draft equals the translated
    snapshot, because check 2 voids any change before `decide`. After Task 4,
    only non-ASCII drafts get translated, so `draft_ascii` is false there in
    practice.
    - `decide` tests RESULT and ERROR before the new rule anyway (#67, #68).
      M4 is killed.
    - A stale result whose draft turned ASCII: check 2 voids it to idle, and
      Enter commits the draft as it appears on screen, never the stale
      translation.
  - **Other Enter variants.** The Shift+Enter branch never reads `draft_ascii`
    (#69), and M12 is killed. Lock is covered by #63 and keypad Enter by #62.
- **Mutation.** 12 mutants.
  - Killed:
    - M1, the rule deleted (#61)
    - M2, the rule returning `translate`
    - M3, the rule above `draft_empty` (#66)
    - M4, the rule above RESULT (#67)
    - M6, `~= nil` (#64)
    - M7, `~= false` (#9)
    - M12, the Shift+Enter branch reading the flag (#69)
  - Equivalent: M5, the rule above ERROR, where both orders give
    `commit_draft`.
  - Survived: M8–M11, which are yellow 1.
- **Step 2's red, reproduced.** The staged test fails against `cf0fb12`'s
  `decide.lua` at #61, with the plan's message.
- **Deviations.** None:
  - The Enter branch, the `commit_draft` comment and the function head are
    byte-identical to the plan's blocks.
  - The test block equals the plan's.
  - Test lines 1-181 are unchanged from `cf0fb12`.
- **Noted for the user, not a finding** (design §5.5, the user's decision).
  Feature 001 taught "Enter, Enter": translate, then commit.
  - On a draft with no Chinese, one Enter now commits, so a habitual second
    Enter reaches the application. In WeChat, that sends the message.
  - This is native Rime's own behaviour, and the IME still triggers no send
    (§2).
  - Task 6's WeChat row (22) covers only a mixed draft. A record row there would
    let someone observe it: `Hello` in Chinese mode, Enter, Enter.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_decide.lua` passes every assertion | ok | `test_decide: 69 assertions OK`, the plan's count. `scripts/run_tests.sh` passes every file. `.githooks/pre-commit` exits 0 over the staged content |
| Enter in idle on a non-empty draft with no byte >= 0x80 is commit_draft, with no backend call | ok | #61-63 cover Return, keypad Enter, and Enter with Lock. `decide` is pure and never references the backend. The processor's `commit_draft` branch (`ime_translate_processor.lua:112-117`) calls no backend. The byte test itself is Task 4's; it was run on samples, above |
| With draft_ascii omitted or false, every earlier decision is unchanged | ok | #1-60 and the 3.1 M-call sweep pass unchanged, with the argument omitted. #64 covers `false` and #65 `nil`. Only #64 covers `false`; yellow 1's fix extends that to the whole key space |

### Verdict
0 red / 1 yellow / 0 green: no red, clear to close. Fix yellow 1, or defer it
with a one-line reason recorded here.

---

### Author response to round 1
- **Yellow 1, fixed.** The catch-all sweep now runs with `draft_ascii` both
  false and true: 6,291,264 calls, about 0.85 s. A new row pins Esc on an ascii
  draft as `noop`. All four surviving mutants now die:
  - M8 at the sweep (Control+Enter)
  - M9 at the sweep
  - M10 at #70
  - M11 at the sweep

  `test_decide` goes to 70 assertions, where the plan said 69. That deviation
  is this fix.
- **The note for the user**, about the Enter-Enter habit on a draft with no
  Chinese, is recorded as Task 6 record row 30 and in decisions.md. It is to be
  raised with the user; it is their §5.5 decision.

---

## Task 3: The raw candidate — round 1

Range: `f1d1c23..HEAD` holds no commit of this task. Task 3 is staged, not
committed, and was reviewed as `git diff --cached f1d1c23`: the new
`rime/lua/ime_translate_raw.lua` and `tests/test_raw.lua`, and
`tests/test_glue_load.lua`. For all three, the staged content equals the
working tree. Not reviewed: `docs/features/002-mixed-input/progress.json`
(ledger state) and `plan/task-06-smoke.md` (a row reorder for a task not
started).
Time: 2026-09-22T05:35Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`rime/lua/ime_translate_raw.lua:2-3`: the reason this module exists is an
  engine claim that the source it rests on contradicts.** The header says that
  without a candidate "there would be nothing to confirm when the processor
  locks it". Design §5.5 says the same (`architecture.md:302-303`: "confirming
  it would do nothing"), and so does the plan (`task-03-raw-translator.md:16-18`).
  No F-row backs it.
  - **Source reading** (librime 1.16.0 `context.cc:168-185`,
    `Context::ConfirmCurrentSelection`, the function F20 cites; not measured).
    The last segment is marked `kSelected` first. With no candidate, only an
    empty segment returns false. A non-empty one falls through the
    `// confirm raw input` branch, fires the select notifier and returns true.
    F20's own row says the same: only "an empty segment with no candidate"
    returns false.
  - **What follows** (derivation, 1.16.0, the functions F20 and F23 cite):
    - `OnSelect` (`engine.cc:259-282`) marks the segment `kConfirmed` at the
      end of the input and opens an empty segment after it.
    - `ClearNonConfirmedComposition` keeps it, since its status is at least
      `kSelected`.
    - `TranslateSegments` skips it (`engine.cc:208`).
    - `GetPreedit` and `GetCommitText` read a confirmed segment with no
      candidate as its raw slice (F5, F23).

    So `jintian`, tap, `readme`, tap, `haode` gives `今天readme好的` with this
    translator or without it.
  - **Consequence.** The component, Task 5's `rime.lua` binding and schema
    change 9's translator line exist for a reason that the cited source
    contradicts.
    - They bring a visible change that no design section weighs and no Task 6
      row observes. Every English run inside a draft opens Squirrel's candidate
      panel with one entry that repeats the letters. That is derived: Squirrel
      builds the panel from `ctx.menu.num_candidates`
      (`SquirrelInputController.swift`, tag 1.1.2).
    - No text is at risk either way. The candidate's text is the segment's
      input slice, which is what `get_commit_text()` returns without it.
  - The spike cannot settle this. Its Lua file was deleted (decisions.md,
    "Feature 002 designed"), and nothing records a run without the translator.
    The spike shows that the translator is sufficient, not that it is needed.
  - **Not the implementer's to settle.** The module and the test match the plan
    byte for byte. Fix, the user's call, through `/design-review` on §5.5 "The
    raw candidate":
    - Either keep it for a reason that holds, for example that the one-item
      panel is wanted as the English-mode cue. Then correct the §5.5 sentence,
      the plan and this header.
    - Or drop it. Then Task 3's module and test go, and Task 5 loses the
      translator line and the `rime.lua` binding.

    Either way, add a Task 6 record row, "in English mode inside a draft, record
    whether a candidate panel shows", so the visible half is observed. Deferring
    until that review is reasonable. Until then, lines 2-3 should cite §5.5 as
    the reason rather than assert engine behaviour.
- **`tests/test_raw.lua:44-48` and `rime/lua/ime_translate_raw.lua:8`: nothing
  tests the `raw` tag check in English mode, the only mode where it does any
  work.** The one non-raw case, #9 ("nothing for a pinyin segment"), runs in
  Chinese mode. There the mode check alone already returns nothing. Two mutants
  of line 8 pass all 9 assertions (run in a scratch copy):
  - M1, the tag check deleted:
    `if env.engine.context:get_option("ascii_mode") then`
  - M3: `if not seg:has_tag("abc") and env.engine.context:get_option("ascii_mode") then`
  - **Where the tag check matters** (F6, a source reading, rechecked at 1.16.0
    `engine.cc:203-232`).
    - Current librime translates the trailing empty segment of a fully
      confirmed composition, with input `""`, and that segment has no tag.
    - A Chinese-to-English tap produces exactly that. The confirm opens an
      empty segment, and `set_option` recomposes it in English mode.
  - **Failure scenario under M1** (derived). Type `jintian`, then tap. The
    translator yields `Candidate("raw", 7, 7, "", "")` on the empty segment.
    - Squirrel shows a panel with one empty candidate right after the tap.
    - Task 6 row 14 (`jintian`, tap, tap, `haode`) diverges. At the second
      tap, the confirm now finds a candidate on the empty segment, so it fires
      the notifier and returns true (`context.cc:173`). §15.5 derives that it
      returns false.
    - No text is lost: the next letter replaces the confirmed empty segment
    (F23, `AddSegment`). But the row's expectation would no longer describe
    the code, and no headless test would say so.
  - This is also R10's shape: a translator answering the empty segment of a
    confirmed composition (upstream.md, "State A"). The empty text makes it
    harmless here. The tag check is the only line that stops it answering at
    all.
  - Fix, checked in a scratch copy. The test goes to 11 assertions, M1 and M3
    die at the first new one, and the staged module passes. The first case is
    the one the engine produces; the second is the acceptance item's own
    wording.
    ```lua
    -- English mode, the empty segment after a lock (F6: translated with input
    -- "", no tag), and a segment not tagged raw
    yielded = {}
    translator("", seg({}, 7, 7), ENGLISH)
    eq(#yielded, 0, "nothing for the empty segment after a lock")
    translator("jintian", seg({ abc = true }, 0, 7), ENGLISH)
    eq(#yielded, 0, "nothing for a segment not tagged raw, even in English mode")
    ```

### 🟢 Suggestions
- **`tests/test_glue_load.lua:18`: the comment "D1: nothing but the processor is
  a rime component" is now false.** Line 4 of the same diff loads a second
  component. D1 dropped the display translator and the filter (decisions.md,
  "D1 closed"), and lines 19-21 check exactly those two names. Someone asking
  whether `ime_translate_raw` breaks D1 would find the test itself saying it
  does. Suggested wording: "D1: the display translator and the filter are
  gone".

### What was walked
- **Red lines 1-5.**
  - The diff has no `ctx:clear`, no `commit_text`, no shell and no Context
    write.
  - `luac -l -l`: the function's only upvalue is `_ENV`. It reads `yield` and
    `Candidate` and writes no global (no `SETTABUP`). `ascii_mode` is read from
    `env.engine.context` on every call. That is the per-session option (F24),
    never cached. A mutant that caches it on the first call dies at #8.
  - **One commit exit (§3.1).** Does the candidate route a commit around the
    processor? Two things show it does not:
    - Its text is the segment's input slice. By F25, `input` is
      `substr(start, end - start)` (`engine.cc:210-211`).
    - With or without it, `GetCommitText` returns the same string (F5, F23).

    It never carries a translation, so display and commit stay apart.
  - **Invalidation (§6.2, after D1: two checks).** Neither is touched. A mouse
    click on the raw candidate confirms the segment and opens an empty one
    after it. The draft stays the same. That is 001 row 22's mechanism, and
    `ime_translate_processor.lua:98-102` already shows the prompt again rather
    than committing unseen.
- **The `lua_translator` contract (F25; librime-lua master, the cached source).**
  - `raw_init` accepts a bare function as the component
    (`lua_gears.cc:96-145`). The module returns one, as the processor does.
  - `Candidate(type, start, end, text, comment)` makes a `SimpleCandidate`
    (`types.cc:242-247`).
  - `start`, `_end` and `has_tag` are `SegmentReg` members.
  - A run that yields nothing leaves the translation exhausted, and `Query`
    returns null (`lua_gears.cc:177-185`). So in Chinese mode the menu is built
    from exactly 001's four translators.
- **The rest of the schema.** Rechecked at 1.16.0.
  - **The four stock translators** decline a segment tagged only `raw`:
    - `script_translator` and `table_translator@custom_phrase` need `abc`
      (`translator_commons.cc:146-147`)
    - `reverse_lookup_translator` needs its own tag
    - `punct_translator` needs `punct` or `punct_number`
  - **The filters.**
    - `simplifier` has no `tags` in this schema, so it applies to every
      segment (`filter_commons.cc:27-37`). It leaves ASCII text alone: a word
      that no dictionary key prefixes returns false, then `ConvertText`
      returns false when unchanged, and the original is kept
      (`simplifier.cc:54-118`, `152-157`, `210-221`). That is a derivation;
      the t2s dictionaries were not dumped.
    - `uniquifier` sees one candidate.
  - **Keys.**
    - `selector` returns early on a `raw`-tagged segment (`selector.cc`, the
      `HasTag("raw")` guard). So the candidate adds no selection keys.
    - In English mode `ascii_composer` takes every printable key first (F19).
  - **The type string `raw`** is librime's own:
    - `echo_translator` uses it for the same kind of candidate
      (`echo_translator.cc:38`).
    - `CommitHistory` records a segment with no candidate under it
      (`commit_history.cc:52`).

    So `punctuator`'s digit-separator check (`punctuator.cc:85`) sees no
    difference.
- **Mutation.** 17 mutants of the module in a scratch copy, one of them an
  identity control. 11 were killed:
  - the mode check deleted, and `and` changed to `or` (#8)
  - the wrong option (#2)
  - `start` changed to 0 (#4), and `_end` changed to `#input` (#5)
  - the text lower-cased (#7), and its spaces stripped (#3)
  - another candidate type (#6)
  - two yields, or none (#2)
  - the mode cached on the first call (#8)

  The survivors:
  - M1 and M3: yellow 2.
  - `_end` changed to `seg.start + #input`: equivalent, since `input` is
    exactly the segment's slice.
  - Capturing `yield` and `Candidate` at load: equivalent in librime-lua.
    `lua_init` runs `types_init` before it loads `rime.lua`
    (`modules.cc:49-85`).
  - A non-empty comment: cosmetic. It would show in the panel, and it has no
    effect on commits.
  - The identity control.
- **Step 2's red, reproduced.** This was a sandbox of `f1d1c23` plus the staged
  tests. Both files fail with `module 'ime_translate_raw' not found`.
- **Deviations.** None. The module and `tests/test_raw.lua` are byte-identical
  to the plan's blocks, and `test_glue_load.lua`'s two lines are the plan's.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_raw.lua` and `lua tests/test_glue_load.lua` pass | ok | `test_raw: 9 assertions OK`, the plan's count. `test_glue_load: 3 modules OK, shared is lazy and stateless`. `scripts/run_tests.sh` passes every file. `.githooks/pre-commit` exits 0 over the staged content |
| Only a raw segment in English mode gets a candidate: the typed text, spanning the segment | ok, with a test gap | Line 8 enforces it: the staged module passes yellow 2's two added cases. #1-7 check one candidate, the text verbatim (spaces and case kept), `start` and `_end` equal to the segment's, and type `raw`. The "only a raw segment" half is not asserted in English mode: yellow 2 |
| Chinese mode is unchanged: fallback_segmentor's raw leftovers get nothing | ok | #8. The mode-check mutants die at #8: deleted, changed to `or`, cached. With nothing yielded, `Query` returns null, so the Chinese-mode menu is 001's |
| Loads headless: no rime global is touched at load | ok | `luac -l -l`: the main chunk is `VARARGPREP`, `CLOSURE`, `RETURN`, with no `GETTABUP`. `yield` and `Candidate` are read only inside the function. `test_glue_load` requires the module with neither global defined |

### Verdict
0 red / 2 yellow / 1 green: no red, clear to close. Fix each yellow or defer it
with a one-line reason recorded here. Yellow 1 is the user's call, through
`/design-review` on §5.5.

---

### Author response to round 1
- **Yellow 1: a design choice, handed to the user as D8.** The reviewer's
  reading holds. The earlier transcript shows that the spike added the
  translator in its first version, on the assumption that a segment needs a
  candidate to be confirmed, and never ran without it. Applied:
  - §5.5's false sentence is corrected, with a note.
  - The §4.1 row and the module's header comment no longer claim that the lock
    needs the translator.
  - D8 (keep or drop) is opened and blocks Task 5 alongside D7.
  - Task 6 gains record row 31, for whether a candidate window shows.
  - Logged in decisions.md.

  Task 3 closes with the module as specified, unwired until D8 decides.
- **Yellow 2, fixed.** The reviewer's two assertions are added: the empty
  segment after a lock, and a segment not tagged `raw`, both in English mode.
  M1 (no tag check) and M3 (`not has_tag("abc")`) now die. `test_raw` goes to
  11 assertions, where the plan said 9.
- **Green 1, fixed.** The comment in `test_glue_load` now reads "D1: the display
  translator and the filter are gone".

---

## Task 4: The processor locks and switches — round 1

Range: `ee2cf0d..HEAD` holds no commit of this task. Task 4 is staged, not
committed, and was reviewed as `git diff --cached ee2cf0d`:
`rime/lua/ime_translate/session.lua`, `rime/lua/ime_translate_processor.lua`,
`tests/test_session.lua` and `tests/test_processor.lua`. For all four, the
staged content equals the working tree. Not reviewed:
`docs/features/002-mixed-input/progress.json`, which is ledger state.
Time: 2026-09-22T05:48Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_processor.lua:54-57`: the fake's `confirm_current_selection`
  always returns true. The real one returns false in the tap's most common
  state, and a regression that reads the result passes every assertion.**
  - **Source reading** (librime 1.16.0 `context.cc`
    `Context::ConfirmCurrentSelection`, `engine.cc` `ConcreteEngine::OnSelect`,
    the functions F20 cites; not measured). A selection that reaches the end of
    the input marks the segment confirmed and opens an empty segment after it.
    That branch of `OnSelect` runs no `Compose`, so the empty segment has no
    menu. A tap then meets it. `ConfirmCurrentSelection` marks it selected, finds
    no candidate and `start == end`, and returns false without firing. The
    second of two taps is the same case (§15.5).
  - The staged code ignores the return value (`ime_translate_processor.lua:92`),
    which is right. Nothing pins that. Mutant C1,
    `if not ctx:confirm_current_selection() then return kAccepted end`, passes
    47 + 120 assertions (scratch copy).
  - **Failure scenario under C1** (derived). `jintian`, space (selecting
    `今天`), tap, `readme`. The confirm returns false, the mode does not switch,
    and `readme` is read as pinyin. Nothing is lost. But select-then-switch is
    the ordinary way into English, and no gate would see it break:
    - Task 6 row 4 excludes a selection before the tap.
    - Rows 1, 5, 6, 17 and 25 tap on an open segment, where the confirm
      returns true.
    - Row 14 (two taps) is the only row where it returns false, and it is
      record-only.
  - This is dimension 8's shape: a fake that returns a fixed value encodes an
    assumption that the cited source (F20) contradicts.
  - Fix, checked in a scratch copy. C1 dies at the new assertion, and the
    staged code passes with 121 assertions:
    ```lua
    -- in fake():
    confirm_current_selection = function(self)
      self.trace[#self.trace + 1] = "confirm"
      return self.confirms ~= false
    end,
    -- in the Shift-tap block:
    -- after a selection that reached the end of the input, or a second tap,
    -- the last segment is the empty one: the confirm returns false (upstream
    -- F20), and the tap still switches (§15.5)
    env, ctx, seg = fake("今天", "jintian")
    ctx.confirms = false
    tap(env)
    eq(trace(ctx), "confirm,ascii_mode=true", "a confirm that finds only the empty segment still switches")
    ```
    Also consider a Task 6 gate row: `jintian`, space, tap, `readme`, expecting
    `今天readme`.
- **The tap makes R16 reachable through `scripts/install.sh` alone. D7 gates
  only Task 5.**
  - D7's row (`decisions.md:23`) reads "Tasks 1–4 go ahead. Task 5, which
    writes the schema, waits", and `progress.sh start` enforces that. The tap
    does not need Task 5, though.
    - The installed schema from 001 Task 10 already puts the processor first,
      with `Shift_L: noop`, `Shift_R: noop`, `Caps_Lock: clear` and
      `good_old_caps_lock: true` (checked in `~/Library/Rime`).
    - `scripts/install.sh:61-66` copies every `rime/lua/ime_translate/*.lua`
      and `rime/lua/ime_translate_*.lua` from the working tree. It has no
      decision check.
  - **Failure scenario** (derived; R16, §15.5). Task 4 is on main and D7 is
    still open. Any `install.sh` run, whether a 001 `/hotfix` or just trying
    the tap, ships the tap. Then: `jintian`, tap, `ok`, Caps Lock, `o`.
    - The Caps Lock press is rejected to the application (F26).
    - The letter carries the Lock bit and is rejected as well.
    - It replaces the whole marked draft, as the spike's R15 measurement saw.
      That breaks §6.3.
  - In 001 the same state could be reached only through `Control+Shift+2`
    (§15.5, "The other switch"). The tap makes it the ordinary path, which is
    exactly what D7's row says 002 does.
  - Not the implementer's to fix in code. The user's call, one of:
    - Record in D7's row that `install.sh` does not run until D7 closes.
    - Make `install.sh` refuse while D7 is open. `open-decisions.sh` is
      already the table's reader.
    - Accept the window explicitly, recorded here.

### 🟢 Suggestions
- **`tests/test_processor.lua:384-388`: the block labelled "a librime-lua with
  no get_time_ms" sets `rime_api = nil`, so it covers only the outer guard.**
  A librime-lua from before #409 (F22) has `rime_api` but no `get_time_ms`.
  - Mutant N1, `local now = rime_api and rime_api.get_time_ms()`, passes. On
    such a build line 59 raises on every key. librime-lua logs the error and
    returns kNoop (`lua_gears.cc` `LuaProcessor::ProcessKeyEvent`), so the whole
    processor is dead and Enter never translates.
  - It cannot happen on this machine: F22 found the name in the installed
    dylib.
  - Running the block once with `rime_api = {}` and once with `nil` kills N1.
    That was checked in a scratch copy, and the staged code passes.
- **`rime/lua/ime_translate_processor.lua:62`: "The state is written only when
  there is some" has no test.** Mutant P6, `if true then`, passes.
  - Consequence: every key writes the property. `Context::set_property` fires
    `OnPropertyUpdate`, which logs an INFO line and sends a `property`
    notification to Squirrel, whose handler ignores it.
  - That is harmless today. Counting the fake's `set_property` calls for one
    letter typed in idle would pin it.

### What was walked
- **Red lines 1-5.**
  - **Never eat text.**
    - The tap path (`:86-98`) has no `commit_text`, no `session.clear` and no
      `ctx:clear()`. Its caret branch only sets `caret_pos`.
    - The new `draft_ascii` route lands in the existing `commit_draft` branch
      (`:145-150`): `commit_text(draft)`, then `session.clear`, then
      `ctx:clear()`. It runs only after the caret rule (`:106`), so `draft` is
      the whole input (F15).
    - The fake's `clear` asserts the red line on every path the suite drives.
  - **One commit exit.** `engine:commit_text` appears only at
    `ime_translate_processor.lua:139` and `:146`. Nothing in the diff
    references `ime_translate_raw`, so Task 4 does not depend on D8. By F20 the
    lock confirms an English segment with no candidate as raw input.
  - **Invalidation** (§6.2 after D1: two checks). Check 1 is unchanged, and the
    Shift press still reaches `decide` and its catch-all. Check 2 still runs
    before the tap path.
  - **Session state.** The Shift state is the Context property
    `ime_translate.shift_down`, never a module variable. P17, which keeps it in
    a Lua global, dies at #112 (the per-box test). `shift_tap` is stateless
    (Task 1).
  - **Shell.** None.
- **Order.**
  - The watcher (`:54-62`) runs before check 2 and before every return.
  - At a tap's release the phase is always idle:
    - The press went through `decide`, and the catch-all voided any
      result/error.
    - No translation can start between the press and the release. Any Enter
      pressed then carries the Shift bit (F21), so it is Shift+Enter.
  - So the tap needs no `session.clear` and no `show`, and check 2 cannot fire
    on the release.
  - That also makes three mutants equivalent in every reachable state:
    - P8, the watcher after check 2
    - P15, the tap path before check 2
    - P16, a `session.clear` in the tap
- **The real engine against the fake** (1.16.0 source).
  - `set_option` fires `OnOptionUpdate`, which runs
    `RefreshNonConfirmedComposition` and then `Compose`, synchronously (F20).
    The processor reads nothing after `set_option`; the log line uses the local
    `ascii`. The fake does not recompose, and it does not need to.
  - The caret setter fires `Compose` (F15). The tap returns immediately after
    it, as Enter's rule does.
  - `confirm_current_selection` fires `OnSelect`. At the end of the input the
    segment is confirmed and an empty segment follows. `_auto_commit` is false
    (`fluid_editor`, `editor.cc:43`), so nothing commits. The other listener,
    `Navigator::OnSelect`, only clears spans. For the return value, see
    yellow 1.
  - `draft` in English mode is the raw slice (F5, F23), with or without the
    raw candidate.
  - `set_property` fires `OnPropertyUpdate`, which calls
    `message_sink_("property", …)`. Squirrel's `notificationHandler` acts only
    on `deploy`, `schema` and `option`.
  - A tapped release returns kAccepted, so `ascii_composer` never sees it.
    With `Shift_L` and `Shift_R` bound to `noop` it has no binding to toggle,
    so its `shift_key_pressed_` can do nothing. `CommitHistory::Push` ignores
    keys with modifiers, so skipping that push changes nothing either.
  - A draft with an earlier open segment, such as an uppercase segment before
    pinyin: the confirm locks only the last segment. Earlier segments stay at
    `kGuess`, `ClearNonConfirmedComposition` pops only from the back, and
    `TranslateSegments` skips them, so they are not read again.
- **`rime_api`.**
  - `RimeApiReg::get_time_ms` returns a `long` of `steady_clock` milliseconds,
    which becomes a Lua integer. So `"keycode@ms"` round-trips through the
    `%d*` pattern.
  - With no `rime_api`, or no `get_time_ms`, `now` is nil and any hold counts
    (green 1 covers the test).
  - The clock is read when the key is processed, as `ascii_composer` reads it.
    A hold during a translation stall is measured after the stall, the same as
    native.
- **Stale state.** The property survives `ctx:clear()` and schema switches,
  which clear only `_`-prefixed properties.
  - A stale `down` needs the processor to miss a release. That happens on a
    focus change, where Squirrel's own `lastModifiers` is stale as well and
    drops the next press anyway.
  - Any other key clears it. With a clock, a stale press is 500 ms or older,
    so it cannot tap.
  - Not a finding.
- **Mutation.** 27 mutants of the processor and session in scratch copies.
  - 18 killed:
    - the order swapped (#84), the confirm deleted (#84)
    - the caret not moved (#103), the caret branch falling through (#104),
      the caret rule skipped (#103)
    - the state never cleared (#96), the clock dropped (#110)
    - the tap falling through to `decide` (#83), always English (#89)
    - the input check replaced by `true` (#91)
    - `draft_ascii` omitted (#116) or always true (#2)
    - the state in a global (#112)
    - a double confirm (#84)
    - the four session mutants: `clear` dropping the state (#41), `at` never
      read, `at` never stored, and a pattern that requires digits
  - 9 survived:
    - C1 is yellow 1, N1 is green 1 and P6 is green 2.
    - P8, P15 and P16 are equivalent (Order, above).
    - P9, `draft ~= ""` in place of `ctx.input ~= ""`, is equivalent. By F15
      the commit text is empty only when the input is.
    - C4, a refresh after the switch, only recomposes the same empty segment.
    - C2 is the identity control.
- **Step 2's red, reproduced.** This was a sandbox of `ee2cf0d` plus the
  staged tests.
  - `test_session` fails with `attempt to call a nil value (field
    'shift_down')`.
  - `test_processor` fails at #83 with `got "2" want "1"`.

  Both are the plan's messages.
- **Deviations.** None.
  - Each of the plan's nine code blocks appears verbatim in the staged files.
  - The counts, 47 and 120, are the plan's.
  - The comments cite F15, F18, F21, F22 and the spike. §5.5 carries F20 for
    the order.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_session.lua` and `lua tests/test_processor.lua` pass; `scripts/run_tests.sh` is all PASS | ok | `test_session: 47 assertions OK` and `test_processor: 120 assertions OK`, the plan's counts. `run_tests.sh` passes all 11 files, and `.githooks/pre-commit` exits 0 over the staged content |
| On a tap with a draft open, `confirm_current_selection` comes before `set_option`; with no draft only the mode switches | ok, with a test gap | #84 and #89 check the trace order, #91 the no-draft case. Order swapped, confirm deleted and input check dropped are all killed. The case where the confirm returns false is untested: yellow 1 |
| A tap commits nothing and clears nothing; Shift+Enter, Shift+letter, Control+Shift and a hold of 500 ms or more are not taps | ok | #85-88, #108 (result phase), #94-101, #110-111. The 500 ms boundary is Task 1's #9/#10. The processor passes the clock through unchanged, and dropping the clock is killed at #110 |
| With the caret inside the input, the first tap only moves the caret to the end | ok | #102-105. All three caret mutants are killed |
| The Shift state lives in a Context property, survives `session.clear()` and is per input box | ok | `test_session` #37-47. `test_processor` #106-107 (a press that voids a result still taps) and #112-113 (per box). `clear` dropping the state and the state in a global are both killed |
| `engine:commit_text()` still appears only in `ime_translate_processor.lua` | ok | grep over `rime/` finds only `:139` and `:146` |

### Verdict
0 red / 2 yellow / 2 green: no red, clear to close. Fix each yellow or defer it
with a one-line reason recorded here. Yellow 2 is the user's call.

---

### Author response to round 1
- **Yellow 1, fixed.** The fake's `confirm_current_selection` now returns
  `self.confirms ~= false`. A new assertion covers a confirm that finds only
  the empty segment, and requires that the tap still switches. The
  confirm-result mutant dies at #114. Task 6 gains gate row 32:
  `jintian`, space, tap, `readme` → `今天readme`.
- **Yellow 2, for the user.** D7's "Until then" cell now says `install.sh` is
  not run until D7 closes, because installing Task 4 would put the tap, and
  R16, live. Logged in decisions.md. The user may accept the window instead.
- **Green 1, fixed.** The no-clock test runs with `rime_api = {}` and with
  `rime_api = nil`. The unguarded `rime_api.get_time_ms()` mutant now errors
  in the test.
- **Green 2, fixed.** A letter with no Shift pending writes no Shift property.
  The write-every-key mutant dies at #115.
- `test_processor` goes to 123 assertions, where the plan said 120. The
  difference is these fixes.

---

## Task 7: Enter and Space — the Enter way — round 1

Range: `6a2af3c..HEAD` holds no commit of this task. Task 7 is staged, not
committed, and was reviewed as `git diff --cached 6a2af3c`:
`rime/lua/ime_translate/decide.lua`, `rime/lua/ime_translate_processor.lua`,
`tests/test_decide.lua` and `tests/test_processor.lua`. For all four, the
staged content equals the working tree. Not reviewed:
`docs/features/002-mixed-input/progress.json`, which is ledger state.
Time: 2026-09-22T06:47Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`docs/features/002-mixed-input/plan/task-06-smoke.md`, rows 2, 6, 17, 21
  and 22: five gate rows still expect Enter to act as it did before this task.
  Under this diff each one fails or cannot be set up.** Task 6 sends a failing
  gate row "back to the task that owns the behaviour", which would be this
  task, and the behaviour is the one the user decided.
  - **Derivation** from librime 1.16.0, not measured:
    - `engine.cc` `TranslateSegments` leaves every segment it translates at
      `kGuess`, whether or not it has a menu.
    - `segmentation.cc` `GetConfirmedPosition` counts only `kSelected` and
      above.
  - **Rows 2 and 6** end on pinyin typed after the last tap (`wenjian`), still
    open. `unselected` is true, so Enter is `lock_literal`. The preedit becomes
    `请你整理一个readmewenjian`, with no prompt. Both rows expect the prompt.
  - **Row 22** is row 4, which ends on an open `haode`, then Enter, Enter.
    - The first Enter locks `haode` as letters.
    - The second translates `今天readmehaode`.
    - Nothing is committed, so "the English is in the input box" fails, and the
      English was made from the wrong draft.
  - **Row 17, English mode.** `hello` is `ascii_segmentor`'s `raw` segment
    (F19), at `kGuess` with an empty menu, so it counts as unselected.
    - The first Enter locks it. On screen, only the highlight range moves.
    - The second translates, and nothing commits.
    - `world` then voids the prompt and joins the draft, instead of going into
      the document.

    **The user's call.** §5.5 says "unselected pinyin" but defines it by the
    confirmed position, and English letters fall short of that too. Either
    English mode takes the extra Enter as well (say so in §5.5 and rewrite row
    17), or an English-mode tail counts as selected, since it is letters
    already. The second is a design change: `/design-review`.
  - **Row 21 cannot be set up.** A translation now starts only when nothing is
    unselected. So the result phase never has an open segment or a candidate
    window to click, and Enter in State B locks instead of translating. 001's
    row 22 path, and the `commit_translation` "off screen" branch it produced,
    become unreachable. They are defensive, not wrong.
  - **Row 45 is ambiguous.** Row 35's sequence already ends ⏎ ⏎ ⏎ (lock,
    translate, commit). Read literally, row 45's ⏎ ⏎ adds a fourth Enter. It
    meets an empty draft, goes to WeChat, and sends.
  - Fix, docs only except row 17:
    - Rows 2, 6 and 22: select the last Chinese before the Enter (␣, then ⏎),
      as §5.5 "A sentence" says.
    - Row 17: decide with the user.
    - Row 21: replace it, for example "State B, ⏎: the open pinyin locks".
    - Row 45: write the sequence out.
- **`rime/lua/ime_translate/decide.lua:55` and `tests/test_decide.lua:234`:
  Shift+Space with nothing unselected commits the whole draft untranslated.
  That is the F27 path this task closes for Space, left open one modifier
  away.**
  - **Source reading**, not measured. Read in librime 1.16.0:
    `gear/ascii_composer.cc` `ProcessKeyEvent`, `recognizer.cc`, `speller.cc`,
    `punctuator.cc`, `selector.cc`, `navigator.cc`, `editor.cc` and
    `key_binding_processor_impl.h`. Also read: the compiled
    `luna_pinyin_translate.schema.yaml` `key_binder`, and Squirrel 1.1.2
    `.keyDown`.
    - Squirrel sends Shift's press, then the space carrying the Shift bit
      (F21).
    - `decide` returns `noop` in idle. In result, the Shift press has already
      voided the translation.
    - Nothing before the editor takes the key:
      - `ascii_composer` passes Shift+space on as a "possible key binding", in
        either mode.
      - The recognizer takes no space without `use_space`.
      - The speller refuses a shifted space, and the punctuator passes a space
        while composing.
      - The selector and the navigator bind no space.
      - This schema's `key_binder` has no Shift+space binding.
    - `fluid_editor` runs its keymap with `FallbackOptions::All`.
      - `{space, Shift}` is not bound, and neither is `{space, Control}`.
      - `IgnoreShift` then finds `{space, 0}`, which is `Editor::Confirm`.
      - `ConfirmCurrentSelection()` is false on the trailing empty segment
        (F20), so `Commit()` runs.
  - **Scenario.** `wo`␣ selects `我`. Space is then pressed while Shift is still
    down for the next word's capital, and `我` goes into the document
    untranslated. With a translation on screen, it is the Chinese that commits.
    Nothing is lost and nothing is sent, which is why this is yellow. But the
    test pins the leak as intended ("shift-space is native").
  - The Esc rule already answers this same fallback (`decide.lua:59-60`, "Esc
    with any modifier").
  - Fix, the implementer's choice:
    - Let `mods == M.SHIFT` into the `literal_space` rule, and flip
      `test_decide` #90-91. Shift+Space on unselected pinyin still goes native
      and selects.
    - Or defer, with the reason recorded here.

    A Task 6 row (`jintian`␣, then Shift+Space) would measure it.

### 🟢 Suggestions
- **`rime/lua/ime_translate_processor.lua:189-194`: with `full_shape` on, the
  "literal space" is U+3000, not a space.** The comment's "a space into the
  draft, confirmed the same way" cites nothing for what the pushed space
  becomes.
  - **Source reading**, not measured: librime 1.16.0 `gear/abc_segmentor.cc`,
    `gear/punctuator.cc` (`PunctSegmentor`, `PunctTranslator`) and
    `gear/fallback_segmentor.cc`, plus the compiled schema and `default.yaml`.
    - `abc_segmentor` refuses a delimiter at a segment's start (`k != j`), so
      the speller's `" '"` delimiter does not pull the space in.
    - `punct_segmentor` runs before `fallback_segmentor` and claims any
      character the current shape defines.
    - The stock `half_shape` has no space, so by default the space falls to
      `fallback_segmentor` as `raw` (F19), and the comment holds.
    - The compiled `full_shape` keeps the preset's space, `{commit: U+3000}`:
      schema change 4 overrides only seven marks.
      `PunctTranslator::TranslateAutoCommitPunct` makes it a candidate, and the
      confirm selects it. Under `fluid_editor` nothing commits.
    - `full_shape` is in `switcher/save_options`, so once toggled with
      Control+Shift+3, it stays on.
  - **Scenario.** Full shape is on. `readme`⏎ ␣ `pull`⏎ ⏎ builds the draft
    `readme`, U+3000, `pull`.
    - `draft_ascii` is false, so Task 2's commit-as-is does not fire, and the
      draft goes to the backend.
    - Shift+Enter commits the ideographic space.

    Nothing is lost.
  - Suggest: cite F19's fallback path in the comment. Then either note the
    full-shape case with a Task 6 record row, or accept it here.
- **`rime/lua/ime_translate_processor.lua:36`: the caret rule's
  `literal_space` entry is unreachable, and §5.5's edge ("The first Enter,
  Space or tap only moves the caret to the end") does not hold for Space.**
  - **Derivation** from F15. With the caret inside, `Compose` rebuilds the
    composition from the input before the caret, or one segment past it when
    the caret sits at the confirmed position.
    - So the confirmed position is at most the caret, and `unselected` is
      true.
    - So `decide` never returns `literal_space` there. Mutant P2, which deletes
      the entry, survives, and is equivalent.
  - **Scenario.** `jintiantianqihenhao`, Left, Space. Native `Editor::Confirm`
    selects the highlighted candidate before the caret, and `OnSelect`
    (`reached_caret_pos`) moves the caret to the end, with the rest pending.
    That is not "only moves the caret". Nothing is lost.
  - Acceptance item 4 holds for Enter, and only vacuously for Space.
  - Suggest: correct §5.5's edge sentence (`/design-review`), and call the
    entry defensive in the comment.

### What was walked
- **Red lines 1-5.**
  - **Never eat text.**
    - Neither new branch calls `ctx:clear()`.
    - `clear_non_confirmed_composition` pops segments, never input, and fires
      no notifier. `GetPreedit` and `GetCommitText` append any input past the
      last segment. So even the "no segment to confirm" return (`:178-181`)
      keeps and shows every letter.
    - For both actions the caret rule only sets `caret_pos`.
    - The only `ctx:clear()` calls are still `:147` and `:154`, each after a
      `commit_text`. The fake's `clear` asserts this on every path the suite
      drives. A mutant that clears in either new branch trips it.
  - **Send is manual.** Both actions and the failure return give kAccepted, so
    neither Enter nor Space reaches the application.
  - **One commit exit.**
    - `engine:commit_text` appears only at `:145` and `:152`.
    - The lock makes no candidate. Its letters reach the application only
      through `get_commit_text` in `commit_draft` or `commit_translation`.
    - `confirm_current_selection` → `OnSelect` never commits. `FluidEditor`
      sets `_auto_commit` false, and `ApplySchema` recreates it after
      `ClearTransientOptions` has dropped the `_` options.
  - **Invalidation.**
    - Check 2 runs first and is unchanged.
    - In result or error, Enter ignores `unselected` (mutant D6 killed).
    - Space in result voids the translation before the push (#149).
  - **Session state.** `unselected` is a local, read fresh on every key.
  - **Shell.** None.
- **`lock_literal` against the engine.** Read in librime 1.16.0 `context.cc`,
  `segmentation.cc`, `engine.cc` and `composition.cc`, and librime-lua
  `types.cc`.
  - **The bindings.**
    - `CompositionReg::back` returns `Segment*`, so the `_end` and `length`
      writes land on the real segment.
    - `toSegmentation` is a `dynamic_cast` of the same object.
    - `Segment(s, e)` sets `length = e - s`.
  - **The clear.**
    - After a selection, `ClearNonConfirmedComposition` pops the open tail.
      `Forward` then pushes `[cp,cp)`: `kVoid`, no tags, no menu. No add is
      needed.
    - With nothing selected, the composition is left empty and `Forward`
      returns false. `AddSegment(Segment(0,0))` pushes the segment, since start
      0 matches `GetCurrentStartPosition`.
    - With the caret at the end, the add cannot fail on the real engine. And a
      non-empty composition always ends in `[cp,cp)` after the clear. So P14
      and P24 are equivalent, and the "cannot be added" test guards a state the
      engine does not reach.
    - A partial selection (`kSelected`, not confirmed) survives the clear. A
      tap's empty `kSelected` segment at `cp` is reused, not duplicated.
  - **The confirm.**
    - It sets `kSelected`. There is no candidate and `end != start`, so the
      select notifier fires (F20).
    - `OnSelect`: `Close` does nothing without a candidate. `end` is the
      input's length, so the segment becomes `kConfirmed`, then `Forward` adds
      `[n,n)`. No `Compose` runs.
  - **Afterwards.**
    - `GetCommitText` and `GetPreedit` give the raw slice: `今天readme`.
    - There is no menu, so no candidate window shows.
    - The confirmed position is the input's end, so the next Enter translates,
      or commits as is (Task 2).
  - **The next key.** `Segmentation::Reset` pops only the segments that end
    past the first changed byte. The locked segment ends at the old end, so it
    stays, and `TranslateSegments` skips it.
  - **BackSpace.**
    - `ReopenPreviousSegment` trims `[n,n)` and reopens the locked segment.
      `start + length` equals the caret, so it goes to `kGuess` with its menu
      still null, and nothing changes on screen. That is why `length` must be
      set (P10 killed).
    - The next BackSpace pops a byte, and the tail is segmented again (R17).
- **`literal_space` against the engine.**
  - **Chinese mode.**
    - `PushInput` runs `Compose`. The trailing `[n,n)` survives the `Reset`.
    - `abc_segmentor` refuses the space (green 1).
    - `fallback_segmentor` pops `[n,n)` and adds `[n,n+1)` as `raw`.
    - If the segment before is a tap-locked `raw` one, it is extended instead,
      and `Clear` resets its status. The processor's confirm then confirms the
      whole `raw` run again, so a tap-locked English word stays locked. The
      lock's own bare segment has no tags, so it is never extended.
  - **English mode.** `ascii_segmentor` takes the space as `raw`, from the
    trailing segment's start.
  - Either way the confirm fires, and `OnSelect` confirms at the end.
  - **The prompt.** `session.clear` and `show` blank it before the push. The
    push's `AddSegment` replaces the segment that held it anyway.
- **`unselected`.**
  - **The caret inside:** always true (green 2).
  - **An empty-but-selected tail** (a tap after a selection): its end is the
    previous segment's end, so the value is right.
  - **After a Shift-tap lock:** the tap's confirm makes the English run
    `kConfirmed`, and Enter translates. English letters with no tap after them
    count as unselected (yellow 1, row 17).
  - **The `ctx.input ~= ""` guard** is equivalent (P5): `0 < 0` is false.
- **Silent failures (F27).**
  - The new line before `decide` runs on every non-tap key while composing,
    Enter in result and Esc included. If it raised, the processor would
    return kNoop with nothing in any log:
    - native Enter would commit the Chinese
    - Space would confirm or commit
    - Esc in result would `CancelComposition` the draft
  - It does not raise. `CompositionReg` has `toSegmentation`,
    `SegmentationReg` has `get_confirmed_position`, and the spike ran exactly
    this chain.
  - Inside `lock_literal` the only other new call is the global `Segment`. It
    is reached only when nothing is selected, a path the spike's `readme`⏎
    covered.
    - Were it missing, the clear would already have run.
    - Native `CommitComposition` would then commit the letters raw. Nothing is
      lost.
- **Tasks 2 and 4, and 001.**
  - `unselected` comes before `draft_ascii` (D1 killed). `Hello`⏎ locks, and
    ⏎ commits. Row 18 was updated for this.
  - The tap returns before `unselected` is read.
  - The caret rule covers the lock (P1 killed, #138).
  - Check 2, Esc and the result/error Enter are unchanged, and the 001 tests
    pass unmodified. The fake's default, "nothing unselected", keeps them on
    the translate path.
- **Mutation.** 32 mutants, in scratch copies of the staged tree.
  - 28 killed:
    - the caret entry for the lock (#138)
    - `unselected` always false (#125), `<=` for `<` (#2)
    - the clear dropped, the add always or never made (#125, #133)
    - `_end` dropped (#127) or off by one (#127); `length` dropped (#128)
    - the lock's confirm dropped; the lock returning kNoop (#124)
    - the guard dropped (error), the failure returning kNoop (#135)
    - the lock setting `ascii_mode`, the lock starting at 0 (#125)
    - Space: `session.clear` or `show` dropped (#149), the confirm dropped
      (#142), kNoop (#141), two spaces pushed (#142)
    - `decide`:
      - the lock after `draft_ascii` (#75), the lock before result (#79)
      - Space with any modifier (the sweep), without the draft check (#89),
        without the unselected check (#87), in idle only (#85)
      - `SPACE = 0x21` (the sweep)
      - Shift+Enter locking (#81)
  - 4 survived, all equivalent on the real engine: P2 (green 2), P5, P14 and
    P24 (above).
- **Step 2's red, reproduced** in a sandbox of `6a2af3c` plus the staged
  tests: `#71 Space is 0x20: got "nil" want "32"` and `#125 the unselected
  part is cleared, then confirmed bare: got "" want
  "clear_non_confirmed,confirm"`. These are the plan's messages.
- **Deviations.** None.
  - All fourteen of the plan's code blocks appear verbatim in the staged
    files.
  - The counts, 92 and 152, are the plan's.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_decide.lua` and `lua tests/test_processor.lua` pass; `scripts/run_tests.sh` is all PASS | ok | `test_decide: 92 assertions OK` and `test_processor: 152 assertions OK`, the plan's counts. `run_tests.sh` passes all 10 files, and `.githooks/pre-commit` exits 0 over the staged content |
| Enter in idle with unselected pinyin: what is not confirmed is replaced by one bare segment over it, then confirmed; nothing committed, nothing translated, the mode untouched | ok | #124-137 in the fake. The source walk above says the real engine does the same, including the empty-composition add. The clear, add, `_end`, `length`, confirm and mode mutants are all killed |
| Space with no modifier, a draft open and nothing unselected: a space is pushed and confirmed; a translation on screen is voided first; otherwise Space is native | ok, with two caveats | #141-152 and `test_decide` #83-92. The Space mutants in `decide` are killed. Shift+Space is native and commits the draft (yellow 2). With `full_shape` on, the pushed space is U+3000 (green 1) |
| The caret rule covers both actions; Shift+Enter, Esc and the result/error phases are unchanged | ok for Enter; vacuous for Space | #138-139, with P1 killed. Space never reaches the rule (green 2). Shift+Enter: #81 and #140. Esc: its branch is untouched and the 001 tests pass. Result and error: #79-80 |
| `engine:commit_text()` still appears only in `ime_translate_processor.lua`; neither action clears the draft | ok | grep over `rime/` finds only `:145` and `:152`. Neither branch has a `ctx:clear()`, and the fake's `clear` assertion never fires |

### Verdict
0 red / 2 yellow / 2 green: no red, clear to close. Fix each yellow, or defer
it with a one-line reason recorded here. Yellow 1's row 17 is the user's call.

---

### Author response to round 1
- **Yellow 1, fixed in the plan**, which has not started. Rows 1, 6 and 22
  select before Enter. Row 21 records that State B with a prompt can no longer
  be reached. Row 45 spells out exactly two Enters, so no Enter lands on an
  empty draft in WeChat.

  Row 17 was the user's call. The user decided that in English mode the open
  part is letters already, so nothing counts as unselected. Enter translates a
  draft with Chinese at once, and commits one with none as is. Whether to
  translate depends on the content, never the mode. Row 17 is correct again;
  new rows 46 and 47 cover this and Shift+Space.
- **Code added after round 1, a deviation from the plan.** The processor's
  `unselected` is now false in English mode. Tests: the mixed draft is
  translated at once, an English-only one is committed as is, and Space in
  English mode pushes a space. The mutant that drops the check dies at #157.
- **Yellow 2, fixed.** Shift+Space takes the literal-space rule too
  (`mods == 0 or mods == SHIFT`). Shift+Space on unselected pinyin stays
  native, and Control+Space is pinned native. The sweep's named row includes
  Shift+Space. The mutant that drops Shift dies at #90.
- **Green 1, deferred.** `full_shape` is off unless toggled. Whether a pushed
  space reaches `get_commit_text` as U+3000 is unverified: the text is the raw
  input slice. Task 6 row 38 would show it if `full_shape` were on.
- **Green 2, fixed in the design.** §5.5 now says Space with the caret inside
  selects, natively, and only Enter and the tap move the caret.
- **Counts.** `test_decide` 94 and `test_processor` 162, where the plan said
  92 and 152. The difference is these fixes. All 11 test files pass.

---

## Task 5: Schema and installer — round 1

Range: `adc0a26..HEAD` holds no commit of this task. Task 5 is staged, not
committed, and was reviewed as `git diff --cached adc0a26`:
`rime/luna_pinyin_translate.schema.yaml`, `scripts/install.sh`,
`tests/test_glue_load.lua`, `docs/design/architecture.md`, and the deletions
of `rime/lua/ime_translate_raw.lua` and `tests/test_raw.lua`. For all six, the
staged content equals the working tree. Not reviewed:
`docs/features/002-mixed-input/progress.json`, which is ledger state. The
real-machine steps were checked against `~/Library/Rime/` and
`$TMPDIR/rime.squirrel/` as they stand.
Time: 2026-09-22T07:11Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`docs/design/architecture.md:209-210` (§5.2) still says "The other ways
  into English with a draft open both discard the draft: Caps Lock (`clear`)
  and `Ctrl+Shift+T`." After this diff, Caps Lock is `noop`. It no longer
  switches to English, and it discards nothing.**
  - The bullet now contradicts §5.5's Caps Lock edge (`:366-369`). It also
    contradicts the §4.1 row this same diff corrected.
  - `inject-design-context.sh` gives §5.2 to every session that edits
    `ime_translate_processor.lua` or `decide.lua`.
  - **Scenario.** Task 6 row 25 or 43 fails and goes back to the processor.
    The fixer gets §5.2, which says Caps Lock losing the draft is the
    inherited behaviour, the one to expect. The schema and §5.5 say the
    capitals must land in the draft.
  - The plan's Step 7 replaced only the next bullet. The implementer went
    past the plan for §4.1 for exactly this reason, so this is the same fix,
    missed. Suggest: "The other way into English with a draft open,
    `Ctrl+Shift+T`, discards it. Caps Lock (`clear`) did too, until D7 made
    it `noop`."
- **`rime/luna_pinyin_translate.schema.yaml:157-158`: the comment over the
  map still calls it "the stock entries except Shift_L (inline_ascii) and
  Shift_R (commit_text)".** `Caps_Lock` now differs from the stock `clear`
  as well (Squirrel's `SharedSupport/default.yaml:70`).
  - **Scenario.** Someone brings the map in line with a later `default.yaml`
    by following the comment: the stock map, with only the two Shifts made
    `noop`. `Caps_Lock: clear` comes back, and with it 001 row 26 and R16:
    - A Caps Lock press clears an open draft through `SwitchAsciiMode`, which
      calls `ctx->Clear()` with no commit.
    - After a tap, the next letter replaces the draft.

    Only the `# 9.` tag on `:162` stands in the way.
  - Suggest: "except Shift_L (inline_ascii), Shift_R (commit_text) and, by
    9., Caps_Lock (clear)".
- **`docs/design/upstream.md:63`: F19's consumer column still says
  "`ime_translate_raw` answers in English mode only". This diff deletes that
  module.**
  - The processor's English-mode rule rests on F19
    (`ime_translate_processor.lua:103-109`, Task 7's fix). In English mode
    the open part is one `raw` segment, and it counts as selected.
  - **Scenario.** A librime upgrade changes `ascii_segmentor`. The maintainer
    looks in F19's consumer column for what to recheck. It names only a module
    that no longer exists, so the processor's English-mode rule and Task 6
    rows 17 and 31 go unchecked.
  - D8's "Applied" list (`decisions.md:760-764`) missed this cell, and this
    task is the one that leaves it pointing at nothing. Suggest: name the
    processor's English-mode rule instead (§5.5, "In English mode"). The cell
    is outside the plan's Files list, so fix it here or defer it with a
    reason.
- **Steps 5 and 6, the log check: the reason given for the deviation is
  wrong.** The plan's `find "$TMPDIR" -name 'rime.squirrel.*.log.ERROR.*'`
  does reach the logs, because `find` recurses.
  - `command find "$TMPDIR" -name 'rime.squirrel.*.log.ERROR.*'` prints
    `$TMPDIR/rime.squirrel/rime.squirrel.<host>.<user>.log.ERROR.<timestamp>.log`.
  - In Claude Code's shell, `find` is a `bfs` wrapper. It also prints
    "Operation not permitted" for the `TemporaryItems` directories under
    `$TMPDIR`, and it exits 1. That is noise, not a missed match.
  - Neither form prints anything newer than the stamp, so acceptance item 4
    stands.
  - **Scenario.** The note is recorded as given. A reader concludes that the
    plan's check could never have found an error log, so every "no error"
    result recorded with it was vacuous. They then distrust or rewrite a
    check that works.
  - Suggest: record it as "scoped to `$TMPDIR/rime.squirrel` to avoid
    permission noise", not as "does not match".

### 🟢 Suggestions
- **`scripts/install.sh:72`: the `sed` misses a quoted list entry.** Rime's
  own build output quotes the entry: line 38 of
  `build/luna_pinyin_translate.schema.yaml` is
  `- "lua_processor@ime_translate_processor"`.
  - **Scenario.** A second component is added as `- "lua_filter@foo"`,
    copied from there.
    - The name list is still non-empty, so no FAILED line prints.
    - `foo` is never bound. It "is created with no error and never runs", in
      the comment's own words.
  - Suggest: allow an optional quote before `lua_`. Today's schema has no
    quoted entry.

### What was walked
- **Red lines 1-5.** The only Lua change is deleting an unwired module.
  - **Never eat text.** Before this diff, `Caps_Lock: clear` cleared a draft
    in `SwitchAsciiMode` with no commit (`ascii_composer.cc:262-265`,
    1.16.0). `noop` closes that path.
    - I walked a Caps Lock press, and letters carrying the Lock bit, through
      the compiled chain.
    - The processor's `decide` masks the Lock bit (R15), and to it the
      `Caps_Lock` keysym is "everything else".
    - `ascii_composer` never enters `ProcessCapsLock`.
    - With no composition, `ascii_composer` rejects the keysym to the
      application. With one, it returns `kNoop`, since `0xffe5` is outside
      `0x20-0x7f`.
    - Nothing else in the compiled schema binds `Caps_Lock`, so no path
      clears.
  - **One commit exit.** `ProcessCapsLock` commits Lock-bit letters itself
    (`engine_->CommitText`, `:179`), but only when `good_old_caps_lock` is
    false. Under `noop` that branch cannot run.
  - **Invalidation, session state, shell escaping.** Not touched.
- **`Caps_Lock: noop` against F26 and F18.** I read `gear/ascii_composer.cc`
  at tag 1.16.0. The installed librime is 1.16.0, according to the build
  info's `rime_version` and a string in the dylib.
  - `load_bindings` skips a `noop` style (`:40-41`).
  - `LoadConfig` leaves `caps_lock_switch_style_` at `Noop` (`:190`,
    `:213-222`).
  - `ProcessKeyEvent` runs `ProcessCapsLock` only when the style is not
    `Noop` (`:68`).
- **What `good_old_caps_lock: true` still does: nothing.**
  - It is read only inside `ProcessCapsLock` (`:151`, `:166`, `:172`).
  - A GitHub code search of `rime/librime` and `rime/squirrel` (default
    branches) finds no other reader, only `ascii_composer.{h,cc}` and the
    changelogs.
  - It matters again only if `Caps_Lock` gets a style back. `true` would then
    bring back R16's rejections, and `false` would make `ascii_composer`
    commit letters itself. `true` is the safer of the two to leave.
- **The binding loop, in a sandbox.** I built a harness from
  `install.sh:22-39` and `:68-85`, run against a stub Rime directory.
  - **A foreign `rime.lua` with no final newline** gets a newline, then the
    binding. A second run prints nothing and leaves `lua_changed=0`.
  - **A missing `rime.lua`** is created with the one line.
  - **A CRLF binding** gets a second, LF binding appended. That is harmless,
    and the old `grep -x` did the same.
  - **A schema with no Lua component** prints FAILED and exits 1.
    - With Lua already copied, the trap prints "Some Lua files are already
      new…" and leaves the pending marker.
    - With nothing copied, no notice prints.
  - **`@name@ns`** binds `name`.
  - **`@*module`** yields an empty word, which the loop drops. That is right:
    F25 says the `*` form needs no global.
- **The machine.**
  - **`rime.lua`** is exactly one line, ending in LF.
  - **`~/Library/Rime/lua/`** has no `ime_translate_raw.lua`. Every installed
    Lua file, and the schema, is `cmp`-equal to the repo.
  - **The built schema** has `Caps_Lock: noop` (`:20`), and its only Lua
    component is the processor (`:38`).
  - **Run 2 changed nothing.** This task left exactly one schema backup,
    `.bak-20260921-235842`, and it still holds `clear`.
    - Both runs fell in the same second: there were two deploys at 23:58:42,
      each "10 success, 0 failure".
    - So a second copy would have overwritten that backup with the `noop`
      version.
  - **Logs newer than the stamp.** Apart from INFO logs, there is only a
    WARNING about the optional `grammar.yaml`, the same line as the 23:18
    deploy's. The only ERROR log is from 16:58.
  - **The restart.** A new process (pid 5956) logs from 23:59:12 and loads
    the built schema. Its log shows `updated property:
    ime_translate.shift_down`, a key only Task 4's `session.lua:12` writes, so
    the new processor is live.
  - **The probe.** The Step 6 preedit comes from the agent's screenshot. The
    logs cannot confirm it.
- **References to `ime_translate_raw`.**
  - A repo grep finds none in code, tests, `install.sh` or the scripts.
  - F19 is yellow 3.
  - The rest are records and stay as they are: the Task 3 plan,
    `plan/README.md:76,97,101`, `progress.json`'s Task 3 entry,
    `decisions.md` and this log.
- **Tests and harness.**
  - `scripts/run_tests.sh` passes 10 files and exits 0. `test_glue_load`
    prints "2 modules OK".
  - `.githooks/pre-commit` exits 0 over the staged content.
  - `setup-harness.sh --check`: the Claude-hook self-test passes 73, the
    git-layer one passes 25, and it reports "harness ready (23 checks)".
  - `test_glue_load` changed only its module list. The assertions left are
    the ones reviewed in Task 3.
- **Deviations.** Every code block in the plan appears verbatim:
  - schema header changes 2, 8 and 9, the `description` and the `Caps_Lock`
    line
  - the `rime.lua` block and the closing hint
  - `test_glue_load`
  - the §5.2 line

  The §4.1 row is an explained improvement. The log check is yellow 4.
- **Out of scope: the restart notice's premise.** This diff leaves the trap
  and the notice unchanged. The evidence is a log reading plus a source
  reading, not a measurement.
  - Pid 65375 started at 23:18, running 001's processor. It wrote
    `ime_translate.shift_down` at 23:58:51, 23:59:00 and 23:59:08.
    - That is after the 23:58:42 `--reload` (`loaded plugin: lua` at
      23:58:42.396) and before the restart.
  - librime-lua `modules.cc` `rime_lua_initialize` (master) builds a new Lua
    state, and reruns `rime.lua`, every time the module initializes.
  - So on this build, `--reload` seems to load new Lua without a restart.
    That contradicts `spike-report.md:144-146` and the notice at
    `install.sh:32-36`.
  - Nothing is at risk, since the notice only asks for an extra restart.
    It is a candidate for an `/issue`.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| The installed rime.lua binds ime_translate_processor once; a second install run changes nothing | ok | `grep -c` gives 1, and the file is that one line. This task's one schema backup still holds `clear`. In the sandbox, a second run prints nothing |
| The built schema has Caps_Lock: noop and no lua_translator | ok | `build/luna_pinyin_translate.schema.yaml:20` is `Caps_Lock: noop`, and `:38` is its only `lua_` line |
| rime/lua/ime_translate_raw.lua and tests/test_raw.lua are gone; scripts/run_tests.sh is all PASS | ok | Both are staged as deleted and are absent from the tree. 10 files PASS, exit 0 |
| The deploy and a Squirrel restart log no Rime error, and the Step 6 probe shows the literal English in the draft | ok; the probe is agent-observed | Neither `find` form prints anything newer than the stamp. Both deploys were "10 success, 0 failure". The new process runs the new processor. The preedit `今天readme` comes from the agent's screenshot |

### Verdict
0 red / 4 yellow / 1 green: no red, clear to close. Fix each yellow, or defer
it with a one-line reason recorded here.

---

### Author response to round 1
- **Yellow 1, fixed.** In §5.2, the "other ways into English" bullet is split:
  - Caps Lock was that way, and discarded an open draft (`clear`). Since
    feature 002 it is `noop` and only types capitals (D7, §5.5).
  - `Ctrl+Shift+T` leaves the schema and discards the draft (§5.1).
- **Yellow 2, fixed.** The schema comment on the `switch_key` map now names
  all three entries that differ from stock: `Shift_L`, `Shift_R` and, by 9.,
  `Caps_Lock`. It says a re-sync must keep them.
- **Yellow 3, fixed.** F19's consumer cell now names the processor's
  English-mode rule, and says `ime_translate_raw` was dropped (D8).
- **Yellow 4, corrected.** The log check was scoped to `$TMPDIR/rime.squirrel`
  to avoid the permission noise of the shell's `find` wrapper. The plan's form
  reaches the logs as well. The earlier "does not match" was wrong. Both forms
  print nothing newer than the stamp.
- **Green, fixed.** The sed accepts an optional quote before `lua_`, as Rime's
  build writes list entries. Sandboxed: `lua_processor@a_one # x` and
  `"lua_translator@b_two"` bind, and `lua_filter@*c_three` is skipped. The
  schema still yields exactly `ime_translate_processor`.
- **Installed again** to carry the schema comment. The installed schema now
  equals the repo, `rime.lua` is unchanged, the build has `Caps_Lock: noop`,
  there is no new ERROR log, and all 10 test files pass.
- **Out of scope, noted for the user.** The reviewer read that `--reload`
  seems to load new Lua without a restart. That contradicts the restart notice
  and the spike report. It is a log reading plus a source reading, with no
  text at risk, and could become an `/issue`.

---
