# Review log

Every task is reviewed by `task-reviewer` before it is marked done. Task 2 is
manual; its record is `docs/smoke-report-004.md`.

---

## Task 1: The Right Option tap switches; Ctrl+Shift+B goes — round 1

Range: `40285afeba68263a1496a514d5933720776c53b6..HEAD` holds no commit of this
task. The work is uncommitted and was reviewed as `git diff 40285af` over the
four deliverables and the four test files (+176 / -86). Not reviewed:
`docs/features/004-option-tap/progress.json`, which is ledger state written by
`progress.sh start`.
Time: 2026-09-22T13:05Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_shift_tap.lua:135`: "Option with Shift is a chord" never holds
  Shift across the tap, so the Shift bit of `RIGHT_OPTION.chord`
  (`shift_tap.lua:24`) is untested.** The Shift_L press in the middle is
  "another key in between" and resets `down` on its own. The plan's Step 1 asks
  for "Shift or Control held", and the Control and Command rows (`:136-137`) do
  hold theirs; this one is an unexplained deviation from it.
  - Mutation: `chord = CONTROL | SUPER` leaves all four files green (42 / 61 /
    109 / 226).
  - Failure scenario under that regression: Shift held, then Right Option
    pressed and released within 500 ms with Shift still down. Squirrel sends
    `Alt_R` with Shift|Alt, then `Alt_R` with Shift|Release (F21, F30), and the
    backend switches. Acceptance item 3 names "Option ... with Shift" as
    switching nothing.
  - The code is right today (probe on a scratch copy: `tapped = false`; with
    the mutation, `true`). Only the lock is missing.
  - Fix: `orun({ k(ALT_R, ALT | SHIFT), k(ALT_R, SHIFT | REL, true) })`
    expecting `"--"`, the form of the Control row.
- **`tests/test_processor.lua:645-648`: "Option+letter is a chord" reuses the
  env the long-hold check (`:641-644`) just used, and passes for the wrong
  reason under the regression it should catch.**
  - Mutation: `ime_translate_processor.lua:96`, `if odown or odown_before then`
    changed to `if odown then`, so a reset is never written back. All 226 stay
    green. The long hold's `down`, pressed at `:641`, survives. The press at
    `:645` meets a pending `down` and is taken as "the other Shift too". The
    release at `:647` is timed from the press at `:641`, more than 600 ms back,
    so it is "no tap", for the wrong reason.
  - The Shift analogue (`if down then` at `:90`) goes red at #96, because
    002's Shift+letter check runs in a fresh env.
  - Failure scenario under the regression, probed with a fresh session and the
    fake clock: Right Option down, `e` (Option+e, the acute dead key), Right
    Option up within 500 ms. `shared.active` flips to `cloud`. And after the
    first tap in a session `down` is never cleared: every later press is a
    "chord", and every later release is timed from that first press. The
    switch works once per input box, then never again.
  - The code is right today.
  - Fix: open the Option+letter case with a fresh `fake(...)`. With that one
    line added, the mutation goes red at `:648` (checked on the scratch copy).
- **`rime/lua/ime_translate_shared.lua:80` still says `shared.switch()` is
  `Ctrl+Shift+B` (design §5.6).** This task removed the hotkey, so the comment
  now names a trigger that nothing produces. Neither 004 task lists this file.
  Task 2 edits the schema, the README and the template, and its acceptance
  item "No Ctrl+Shift+B remains in the schema, the README or the template"
  passes with this line still in place.
  - Scenario: the user reports that the switch does nothing. Whoever reads
    `shared.switch()` is sent to a key binding that no longer exists, not to
    the watcher at `ime_translate_processor.lua:94-96, 137`.
  - Fix: "A lone Right Option tap (design §5.6)". One line. Or defer it by
    adding the file to Task 2's list.

### 🟢 Suggestions
- None with a failure scenario.

### What was walked
- **Plan against implementation.**
  - The interfaces match the plan:
    - `observe(down, key, now, tap)`, defaulting to `SHIFT`.
    - `RIGHT_OPTION = { codes = { [0xFFEA] = true }, chord = SHIFT | CONTROL |
      SUPER }`.
    - `option_down` / `set_option_down` under `ime_translate.option_down`,
      through a shared `read_down` / `write_down`.
    - `decide` has no `KEY_B`, no branch and no doc line for the action.
  - `switch_backend` (`processor:51-64`) is the removed 003 branch, statement
    for statement: void, `S.switch()`, notice on then off, log, `kAccepted`.
  - The watcher is at `:94-96`, beside the Shift watcher, before check 2 and
    every return. The dispatch is at `:137`, after the Shift tap block.
  - Additions, each explained in its own comment: the three `Alt_R` rows at
    `test_decide.lua:254-257` and the clock restore at `test_processor.lua:634`.
    The one unexplained deviation is yellow 1.
- **Step 2, re-run.** The new tests against the baseline modules
  (`git show 40285af`, all four) all fail:
  - test_shift_tap #29 (the exports list)
  - test_session at `:136` (`option_down` is nil)
  - test_decide #57: the sweep finds `0x42` mod `0x5` returning
    `switch_backend`
  - test_processor #164: the tap returns kNoop
- **Red line 1, never eat text.** No `ctx:clear()` was added. The two there
  are, `processor:191` and `:198`, each follow their `commit_text`.
  - `switch_backend` calls `session.clear`, which touches properties only, and
    `show`.
  - Every tap test asserts `#env.committed == 0` (`:586, 604, 630, 666`).
  - The fake's `clear()` asserts that a commit came first.
- **Red line 2.** `commit_text` appears only in the processor.
  `checks_lua_invariants` is clean on all eight files.
- **Red line 3, invalidation.**
  - The Right Option press reaches decide's catch-all. The sweep covers
    `0xFFEA` under `ALT`: `invalidate_and_pass` in result and error, `noop` in
    idle. It is also pinned at `test_decide.lua:255-256`.
  - Check 2 is unchanged, and the new watcher has no return.
  - D1 is closed; `progress.sh decisions` lists none open.
- **Red line 4.** The Option state is a Context property. The module-level
  additions are constant descriptors: nothing that would differ per input box.
- **Red line 5.** No shell path was touched.
- **Point 1, the void before the switch.**
  - In result and error the press voids through the catch-all
    (`processor:243-246`, kNoop, asserted inside `otap` at
    `test_processor.lua:564`), and the release switches.
  - The void inside `switch_backend` is then redundant on every reachable
    path. Removing it leaves 226 green, and so does gating the switch on phase
    idle. Neither changes behaviour: between a press and its tap release no
    key can bring back result or error. It stays as the plan's "unchanged"
    move; not a finding.
- **Point 2, the two watchers.**
  - Each descriptor accepts only its own keysyms and resets on any other
    (`shift_tap.lua:33`). A Right Option press resets a pending Shift, a Shift
    press resets a pending Option, and the two `tapped` flags cannot both be
    true for one key.
  - The Shift descriptor has the old `CHORD` (`0x4|0x8|0x4000000`) and the
    same two codes. 002's test blocks are unchanged and green. Dropping Alt
    from `SHIFT.chord` goes red at test_shift_tap #16.
  - Mutations that go red:
    - the Option watcher reading the Shift property: #164
    - `K_OPTION` set to the Shift property's name: test_session #58,
      test_processor #83
    - the Shift watcher given the Option descriptor: #83
    - the default descriptor swapped: test_shift_tap #5
  - Two placement mutations stay green, and neither placement can fail with
    Squirrel's events:
    - The Option watcher moved below the stale-Esc return: an Option press
      voids the phase itself, so that return cannot fire before its release.
    - The Option watcher moved below the Shift tap return: a Shift press with
      Option held carries Alt, so it is never a Shift tap.
- **Point 3, the chord mask, against Squirrel 1.1.2.**
  - Fetched `sources/SquirrelInputController.swift` and
    `sources/MacOSKeyCodes.swift` at tag 1.1.2.
  - In `handle(_:client:)`, the `.flagsChanged` case:
    - `rimeModifiers = osxModifiersToRime(event.modifierFlags)` is the mask
      after the change.
    - A flag being set appends `(rimeKeycode, rimeModifiers)`.
    - A flag being cleared inserts `(rimeKeycode, rimeModifiers |
      kReleaseMask)` first.
  - `osxModifiersToRime` maps `.option` to `kAltMask` (0x8).
  - `keycodeMappings` maps `kVK_RightOption` to `XK_Alt_R` and `kVK_Option`
    to `XK_Alt_L`.
  - So the press is `0xFFEA` with Alt, and the release is `0xFFEA` with
    Release and no Alt. F21 and F30 hold, and `RIGHT_OPTION.chord` must leave
    Alt out.
  - The same code also shows that with one Option held, the other changes no
    `.option` flag and sends nothing. A Left+Right combination never reaches
    the watcher as a Right Option press.
- **Point 4, the fixture.**
  - The no-clock loop (`test_processor.lua:433-439`) leaves `rime_api = nil`.
    003's blocks up to `:630` run with no clock, where a tap counts at any
    hold, which they need.
  - `:634` restores the clock over the same `clock` upvalue.
  - The long-hold check depends on it: giving the Option watcher `nil` for
    `now` goes red at #200.
- **Point 5, nothing left over.**
  - `switch_backend` exists only as the local function (`processor:51, 137`).
    decide's action list and code have none.
  - `KEY_B` and `KEY_LOWER_B` are gone, and `NOTICE` is still used.
  - test_decide's `T` went with its row: Ctrl+Shift+T is now covered by the
    sweep's `CTRL | SHIFT` set.
  - `Ctrl+Shift+B` remains in the schema (`:25, :40`), the template (`:15`)
    and the README, all Task 2's, and at `ime_translate_shared.lua:80`
    (yellow 3).
- **The implementer's mutations, re-run.** All three confirmed:
  - Alt in the Option chord: red at test_shift_tap #31 and test_processor
    #164.
  - The processor hook removed: red at #164.
  - Left Option in the codes: red at test_shift_tap #35 and test_processor
    #198.
- **Dimension 8.**
  - The comment at `processor:91-93` cites F21 and F30.
  - "Applications do not take [a flag change] for themselves" is the design's
    own derivation (§5.6; decisions.md, "Feature 004 designed").
  - Task 2's smoke measures it in TextEdit, Chrome and a terminal.
- **Language and hooks.** `checks_language`, `checks_lua_invariants` and
  `checks_secrets` are clean on all eight files. The hook suites were not run:
  the task touches no hook.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | rc 0, all 11 files PASS: test_processor 226, test_decide 109, test_session 61, test_shift_tap 42 |
| A Right Option press and release within 500 ms, alone, switches the backend in every phase, with or without a draft, and commits nothing | ok | test_processor, by case: idle with a draft `:582` (no cloud slot, notice only); result `:597`; no draft `:625`; error `:657`; caret inside `:671`; English mode `:681`. `#env.committed == 0` at `:586, 604, 630, 666`. 499 ms is a tap at test_shift_tap `:131` |
| Left Option, a hold of 500 ms or more, Option with another key or with Shift, Control or Command, and Ctrl+Shift+B switch nothing | ok in the code, two locks missing | Left Option: processor `:638-640`, test_shift_tap `:133`. The hold: 500 ms at test_shift_tap `:132`, 600 ms at processor `:641-644`. Control and Command: test_shift_tap `:136-137`. Ctrl+Shift+B: processor `:636`, test_decide `:246-252`. Shift held rests on a probe, not a test (yellow 1). The processor's Option+letter check is masked (yellow 2) |
| The Shift tap behaves exactly as before | ok | The same codes and chord bits as the old `CHORD`. 002's test blocks are unchanged and green. The default descriptor is checked at test_shift_tap `:142-147` |

### Verdict
0 red / 3 yellow / 0 green: no red, clear to close. The three yellows should
be fixed, or deferred with a reason, before the commit.

### Resolution (implementer, after round 1)

- **Yellow 1, fixed.** `test_shift_tap` holds Shift through the whole Right
  Option tap. `chord = CONTROL | SUPER` now fails at #38.
- **Yellow 2, fixed.** The processor's Option+letter case starts from a new
  input box. Not writing back the reset state now fails at #202.
- **Yellow 3, fixed.** `ime_translate_shared.lua`'s comment on `switch()`
  names the Right Option tap and where the processor watches for it.
- `scripts/run_tests.sh`: 11 files PASS.
