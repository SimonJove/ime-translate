# Review log

Every task is reviewed by `task-reviewer` before it is marked done; the
procedure is `.claude/skills/task-review/SKILL.md`. Any 🔴 means another round,
and **each round is appended, never overwritten**.

Documentation-only tasks are not reviewed. Task 6 is manual; its record is
`docs/smoke-report-003.md`.

---

## Task 1: The cloud slot in the config — round 1

Range: `882d08d6e60e56b60405a20e3dfda2d26c8f088c..HEAD` holds no commit of this
task. The work is uncommitted and was reviewed as `git diff 882d08d` on its two
deliverables, `rime/lua/ime_translate/config.lua` and `tests/test_config.lua`.
Not reviewed: `docs/features/003-backend-switch/progress.json`, which is ledger
state written by `progress.sh start`.
Time: 2026-09-22T11:17Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_config.lua:169-170` and `:175-179`: three of the eight per-slot
  keys are never exercised, so their routing can regress with every assertion
  green.** `prompt`, `temperature` and `max_tokens` are never written under
  `cloud_`, and never set locally beside a cloud slot. #88 (`temperature` is
  0.2) and the `prompt` assert at :170 compare the cloud slot with the default
  while the local slot also holds the default, so they cannot tell "took the
  default" from "inherited the local value". On a scratchpad copy, each of
  these leaves all 122 assertions green:
  - `config.lua:171` skipping `prompt`, `temperature` and `max_tokens` when it
    copies the given `cloud_` keys into the slot
  - removing `prompt`, `temperature` or `max_tokens` from `SLOT_KEYS`
    (`config.lua:34-36`), which makes that key shared

  Failure scenario: the cloud slot is anthropic, with `cloud_max_tokens: 2048`
  and a custom `cloud_prompt`. Under the first regression both are accepted
  with no warning and have no effect: the slot sends the default prompt and
  1024. Under the second, `cloud_temperature: 0.5` is an unknown key and the
  cloud slot inherits the local `temperature`, which acceptance item 3 forbids.
  The current code is correct (probes below); only the lock is missing. The
  gap comes from the plan's Step 1, which the test transcribes verbatim. Fix:
  one load that sets all three locally with a `cloud_backend` and asserts the
  cloud slot holds the defaults, and one that sets all three under `cloud_` and
  asserts they are read.

### 🟢 Suggestions
- **`tests/test_config.lua:202-204` and `:197-200`: the wording of the cloud
  warnings is unpinned.** Two mutations survive: the range-reset warning at
  `config.lua:177` naming `timeout_ms` instead of `cloud_timeout_ms`, and the
  drop warning at `config.lua:174` losing its `cloud slot dropped:` prefix.
  Scenario: `cloud_timeout_ms: 20000` would log
  `config: timeout_ms out of range [500,10000]; fell back to default`, word for
  word the local slot's warning. The user checks `timeout_ms`, finds nothing
  wrong, and never learns the cloud timeout was reset to 1500. Two asserts
  close it: `wct[1]:find("cloud_timeout_ms")`, and
  `w:find("^cloud slot dropped")` inside the existing loop.
- **Design-level, not a defect of this task: a cloud slot with no
  `cloud_base_url` is silently a loopback slot** (`config.lua:168-172`, as
  backend.md §9's first bullet prescribes). Say the user sets
  `cloud_backend: anthropic`, `cloud_model` and `cloud_api_key_account` and
  forgets `cloud_base_url`. The result is an anthropic slot at
  `http://127.0.0.1:8989`, which passes the trust tier as loopback with no
  warning (probed). Once Tasks 3 and 4 wire it:
  - every cloud Enter posts to the local translate server's `/messages`,
    carrying the Anthropic key in `x-api-key` over loopback http
  - the server answers 404, so every translation is `http_error`
  - the prompt shows `->`, not `☁`, since the marker follows the URL

  Nothing leaves the machine and nothing is eaten. The local slot has behaved
  the same way since v1 (`backend: anthropic` without `base_url`). Whether a
  cloud slot left at the loopback default deserves a warning is a
  `/design-review` question, not a change for this task.

### What was walked
- **Plan against implementation.** `config.lua` matches Step 3 line for line.
  The only differences are comments:
  - the parse-loop comment at :117-118 is the plan's prose, moved into the code
  - the old "names the key, not the value (§7.3)" note now sits in
    `refusal`'s doc comment at :71-72

  There is no behavioural deviation. The appended test block (:152-220) is
  byte-identical to Step 1 (diffed).
- **Step 2, re-run.** The new tests against the baseline `config.lua`
  (`882d08d`) fail at #77, `a valid cloud slot warns nothing`, with 5
  warnings, as the plan predicts.
- **The local checks, moved into `refusal`.**
  - The three warning strings are exactly the baseline's.
  - The first failure still wins. An unknown backend resets the triple to the
    loopback default, so the old trust check could never fire after it.
  - The baseline test file (75 assertions) passes unchanged against the new
    `config.lua`. The diff removes no test line.
- **Mutations**, on a scratchpad copy; the working tree was not touched.
  - Red:
    - the cloud refusal removed, or reading `out` instead of the slot (#107)
    - the shared keys taken from DEFAULTS (#77)
    - the cloud range check removed (#114)
    - the orphan-keys warning removed (#117)
    - a drop warning naming the URL or backend (the value-free loop)
    - a loose `cloud` prefix (#121)
    - any DEFAULTS key routable under the prefix (#119)
    - any `cloud_` key making a slot (#116)
    - `cloud_` keys also written to the local slot (#80)
    - the slot carrying a `cloud` field (#89)
    - the non-number warning naming the bare key (the find after #122)
    - a failed slot replaced by the default backend (#107)
    - the `max_chars` range check removed (#23)
    - the local fallback resetting only `backend` (#25)
    - `api_key_account` made shared (#77)
  - Survived:
    - the per-slot routing of `prompt`, `temperature` and `max_tokens`
      (yellow 1)
    - the two warning texts (green 1)
    - the unknown-key warning naming the bare key. This one is an
      equivalent mutant: every routed key is in DEFAULTS, so that branch
      only ever sees unrouted keys.
- **Probes of the current code.** All of these behave correctly:
  - the local `prompt`, `temperature` and `max_tokens` are not inherited, and
    the `cloud_` ones are read
  - a failing local slot beside a valid cloud slot: the cloud slot stays, with
    one warning
  - both slots remote without `allow_remote`: two warnings; the local slot
    falls back and the cloud slot is dropped
  - `cloud_backend` given twice: the last one wins
  - `cloud_allow_remote`, `cloud_debug_log` and `cloud_max_chars`: unknown
    keys
  - `allow_remote: yes` with a remote cloud: `allow_remote` resets and the
    slot is dropped
  - a dropped slot with a bad timeout: one warning
  - `cloud_backend:` left empty, with other `cloud_` keys: the orphan-keys
    warning
  - glob and userinfo cloud URLs: dropped
  - a quoted cloud value with a comment: parsed
  - `cloud_` and `cloud_cloud_backend`: unknown keys
- **Consumers.** Only `ime_translate_shared.lua:33` and the tests call
  `config.load`. Nothing iterates `settings` with `pairs`, so the nested
  `settings.cloud` table reaches no logger or serializer. `backend.lua` reads
  named fields only.
- **Red lines 1-5.** Untouched: the diff has no `ctx:clear`, no
  `commit_text`, no session state and no shell command. `SLOT_KEYS` and
  `CLOUD` are read-only module constants, and the working `cloud` table is
  local to `load`. By the §6.1 test, neither differs between input boxes.
- **Dimensions 7-9.**
  - The cloud `timeout_ms` defaults to 1500, from DEFAULTS, with the local
    range [500,10000].
  - Every new warning is a constant or names a key, never a value (§7.3).
  - The diff makes no upstream claim.
  - Nothing is built beyond §9.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| lua tests/test_config.lua passes every assertion | ok | `test_config: 122 assertions OK`; `scripts/run_tests.sh`: 10 files PASS |
| With no cloud_ keys, settings.cloud is nil and every earlier assertion passes unchanged | ok | #76. The baseline test file's 75 assertions pass against the new `config.lua`; no test line is removed |
| An unset cloud key takes the default, not the local slot's value; allow_remote, max_chars and debug_log are shared | ok, partly locked by tests | #101-#103 lock `timeout_ms`, `model` and `base_url`; #87 and #104-#106 lock the shared keys. `prompt`, `temperature` and `max_tokens` are verified only by probe (yellow 1) |
| A cloud slot failing the adapter or trust check is dropped with one warning that names no value; the local slot is untouched | ok | #107-#113, #109, and the value-free loop at :197-200. A probe with both slots failing shows the local fallback unaffected by the cloud drop |

### Verdict
0 red / 1 yellow / 2 green: no red, clear to close. Fix the yellow, or defer it
with a one-line reason recorded here.

---

### Resolution (implementer, after round 1)

- **Yellow 1, fixed.** `tests/test_config.lua` now sets `prompt`,
  `temperature` and `max_tokens` on the local slot and checks that the cloud
  slot keeps the defaults. It also sets all three under `cloud_` and checks
  that they are read, with no warning, and that the local slot is untouched.
  - Dropping `temperature` from `SLOT_KEYS` now fails at #123.
  - Skipping `max_tokens` in the cloud copy fails at #128.
  - `test_config: 130 assertions OK`.
- **Green 1, taken.** Two `find` assertions pin the wording:
  `cloud_timeout_ms` in the reset warning, and `cloud slot dropped:` at the
  start of the drop warning.
- **Green 2, a design question, not a defect of this task.** A cloud slot
  with no `cloud_base_url` gets the loopback default, as §9 says. It is open
  as D9 in `docs/design/decisions.md`, for the user; it blocks nothing.

---

## Task 2: Ctrl+Shift+B in decide — round 1

Range: `d65af5d2d69aaa64030f03e75c2cfc40a0cadd3e..HEAD` holds no commit of this
task. The work is uncommitted and was reviewed as `git diff d65af5d` on its two
deliverables, `rime/lua/ime_translate/decide.lua` and `tests/test_decide.lua`.
Not reviewed: `docs/features/003-backend-switch/progress.json`, which is ledger
state written by `progress.sh`.
Time: 2026-09-22T11:28Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_decide.lua:246-251`: "draft open" is locked only for a draft
  that holds Chinese and has nothing unselected.** The loop calls `is()`,
  which passes neither `draft_ascii` nor `unselected` (`:7`). `named_row`
  (`:134`) takes B under `CTRL | SHIFT` out of the sweep. So no assertion
  reaches the `switch_backend` branch with either flag true. The processor
  computes both on every key (`ime_translate_processor.lua:109-112`). On a
  scratchpad copy, each of these leaves all 109 assertions green:
  - `and not unselected` added to the condition at `decide.lua:42`
  - `and not draft_ascii` added there instead

  Failure scenario: the first is a plausible edit, because F29's derivation
  says the switch notice is hidden by the candidate list while pinyin is
  unselected, so "don't switch where the user can't see it" reads like a fix.
  Under it, the user types `nihao` with the candidates up and presses
  Ctrl+Shift+B. decide returns `noop`, the key goes on natively, and the
  backend does not switch. The Enter that follows translates with the old
  backend. That breaks §5.6 ("in every phase, with or without a draft") and
  acceptance item 2, with every test green. The current code is correct (probe
  below); only the lock is missing. The gap comes from the plan's Step 1, which
  the test copies verbatim. Fix: run the phase loop through `is5` with
  `ascii` and `unsel` each set false and then true, as the sweep does for every
  other key (feature 002 review, yellow 1). Or add rows for an
  unselected-pinyin draft and an ASCII-only draft.

### 🟢 Suggestions
- **`tests/test_decide.lua:252`: the row labelled "Shift with Caps Lock on"
  has no Lock bit, and no test pins the event Caps Lock actually produces.**
  Squirrel's `osxModifiersToRime` sets `kLockMask` whenever Caps Lock is on
  (spike R15). `osxKeycodeToRime` leaves the letter lowercase only when
  `shift == caps` (F29, re-read in `MacOSKeyCodes.swift`). So the Caps Lock
  case is `0x62` with `CTRL | SHIFT | LOCK`:
  - #101 tests `0x62` without Lock
  - #102 tests Lock with `0x42`
  - the sweep exempts both codes

  One mutation stays green on all 109: checking the lowercase code against the
  raw modifier,
  `(code == M.KEY_B and mods == M.CONTROL | M.SHIFT) or (code == M.KEY_LOWER_B and key.modifier == M.CONTROL | M.SHIFT)`.
  Failure scenario: with that mutation, Caps Lock on and
  `charactersIgnoringModifiers` giving lowercase, Ctrl+Shift+B does nothing
  and every test stays green. Fix: `CTRL | SHIFT | LOCK` on that row, or a
  second row that has it.

### The deviation from the plan, judged
The sweep gained `CTRL | SHIFT` and `CTRL | SHIFT | LOCK` (`:138-139`).
`named_row` exempts `0x42`/`0x62` under `CTRL | SHIFT` only (`:134`). The
comments at `:133` and `:137` explain both in place. **This is an improvement,
not an omission.**
- Under the plan's test (the baseline sweep plus the appended block), widening
  the match to `0x43` leaves all 109 green. Under the deviation it fails at #57.
  The same holds for a bad `KEY_B` constant (`0x41`): the sweep catches it too,
  at #57.
- The sweep now proves decide takes none of the native Control+Shift bindings
  in the compiled schema (`~/Library/Rime/build/luna_pinyin_translate.schema.yaml:78-91`):
  Control+Shift+1 to 5, exclam, at, numbersign, dollar, percent and T. The
  processor runs first, so a decide that took one of them would silently
  disable a `key_binder` binding.
- The exemption is narrow. B and b under every other modifier set are still
  swept, which covers Ctrl+B, Shift+B and Ctrl+B with Lock. B under
  `CTRL | SHIFT` is pinned by #95-#100 and #102.
- Cost: from 12.6M to 15.7M calls; the file's run time goes from 2.0 s to
  2.5 s. The purity sweep at `:177-190` reuses `MODSETS` and gains the two sets
  too, which does no harm.

### What was walked
- **Plan against implementation.**
  - `decide.lua` matches Step 3 line for line (diffed; the only extra is one
    blank line).
  - The test block at `:244-260` is byte-identical to Step 1.
  - The sweep is the only deviation.
- **Step 2, re-run.**
  - The new test against the baseline `decide.lua` fails at #95,
    `ctrl+shift+B, idle, draft empty: got "noop" want "switch_backend"`, as
    the plan predicts. The sweep stays green there: B is exempt, and the other
    Ctrl+Shift keys were already catch-all.
  - The baseline test file (94 assertions) passes against the new
    `decide.lua`.
- **Mutations**, on a scratchpad copy; the working tree was not touched.
  - Red:
    - lowercase b dropped (#101)
    - `mods & CONTROL ~= 0` (#57)
    - the match widened to `0x43` (#57)
    - Lock not masked, `key.modifier == CONTROL | SHIFT` (#102)
    - extra modifiers allowed, `mods & (CONTROL | SHIFT) == CONTROL | SHIFT`
      (#107)
    - idle only (#97)
    - no error phase (#99)
    - a draft required (#95)
    - the check placed ahead of the release check (#103)
    - any key under Ctrl+Shift (#57)
    - `KEY_B = 0x41` (#57)
    - Shift alone (#57)
    - Control alone (#57)
    - a misspelt action type (#95)
  - Survived:
    - gating on `unselected` or on `draft_ascii` (yellow 1)
    - the lowercase code checked against the raw modifier (green 1)
    - the B branch writing to `key`: the purity sweep's code list has no B.
      This has no consequence, because the processor builds a fresh `k` for
      each event (`ime_translate_processor.lua:53`) and nothing reads it after
      decide.
    - the check moved below the Enter, Space and Esc branches. This one is
      equivalent: B is none of those keys.
- **Probe of the current code.** Squirrel can send four events for
  Ctrl+Shift+B: `0x42` or `0x62`, each with `CTRL | SHIFT` or with Lock added.
  The probe also added stray Mod2, Mod4 and release-mask bits. Every
  combination returns `switch_backend` in idle, result, error and busy, with
  the draft empty or open and `unselected` true or false.
- **Upstream (dimension 8).** `decide.lua:12-14` cites F29. The claim was
  re-read in the Squirrel 1.1.2 sources that the feature 003 design review
  fetched into the scratchpad (a source reading):
  - With Control held, `capitalModifiers` is false and the key chars are
    `charactersIgnoringModifiers` (`SquirrelInputController.swift:100-106`).
  - `osxKeycodeToRime` uppercases a lowercase letter if and only if
    `shift != caps`. A letter falls back to `additionalCodeMappings` (`XK_b`,
    lowercase) only when its key char is not printable ASCII. That is `0x62`
    too, so it is covered as well.
  - `osxModifiersToRime` maps Control to `kControlMask` (0x4) and Caps Lock to
    `kLockMask`.
  - Command keys are dropped before Rime (`:96`), so the Command row is a
    second safeguard.
- **Native bindings.** Neither the compiled schema nor `default.yaml` binds
  Control+Shift+B or Control+Shift+b, so taking the key shadows nothing.
  `Control+b` (emacs Left) is a different event and stays catch-all (#104,
  #105 and the sweep).
- **The state until Task 4.** The processor has no `switch_backend` branch
  yet, so the action falls through to `return kNoop`
  (`ime_translate_processor.lua:207`). In result, the key passes without
  voiding. The draft is unchanged, so nothing stale can be committed, and
  check 2 covers any native edit. The void on a switch is Task 4's acceptance
  item 2.
- **Red lines 1-5.** The diff has no `ctx:clear`, no `commit_text`, no
  session state and no shell command. `KEY_B` and `KEY_LOWER_B` are read-only
  module constants.
  - Dimension 3: in result and error, Ctrl+Shift+B no longer returns
    `invalidate_and_pass`. The §5.2 row allows this; the void moves to the
    processor (Task 4).
  - D1 is closed, and the diff touches no session, processor or translator.
- **Hard checks.** `checks_gate`, `checks_lua_invariants`, `checks_secrets` and
  `checks_language` are clean on both files.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| lua tests/test_decide.lua passes every assertion | ok | `test_decide: 109 assertions OK`; `scripts/run_tests.sh` exits 0, every file PASS |
| Ctrl+Shift+B is switch_backend in idle, result and error, draft empty or open; the Lock bit is ignored | ok, partly locked by tests | #95-#100 and #102. "Open" is locked only with `draft_ascii` and `unselected` unset (yellow 1); the probe shows the code is correct for both |
| Its release, Ctrl+B, Shift+B, and Ctrl+Shift+B with Alt or Command are not; Ctrl+Shift+T stays native | ok | #103-#109; the sweep (#57) covers every other key under Ctrl+Shift, with Lock and without |

### Verdict
0 red / 1 yellow / 1 green: no red, clear to close. Fix the yellow, or defer it
with a one-line reason recorded here.

### Resolution (implementer, after round 1)

- **Yellow 1, fixed.** The phase loop now runs through `is5`, with
  `draft_ascii` and `unselected` each false and true: 24 cases.
  `and not unselected` added to the branch now fails at #96.
- **Green 1, taken.** The Caps Lock row carries `CTRL | SHIFT | LOCK`, as
  Squirrel sends it (R15, F29), and a second row keeps the lowercase letter
  with no Lock bit. The mutation that compared the raw modifier for `b` now
  fails at #119.
- `test_decide: 128 assertions OK`.

---

## Task 3: The active slot and the cloud marker — round 1

Range: `445fe16be63113bc54ef015913d676819999d5d1..HEAD` holds no commit of this
task. The work is uncommitted and was reviewed as `git diff 445fe16` on its four
deliverables:
- `rime/lua/ime_translate_shared.lua`
- `rime/lua/ime_translate/session.lua`
- `tests/test_shared.lua`
- `tests/test_session.lua`

Not reviewed: `docs/features/003-backend-switch/progress.json`, which is ledger
state written by `progress.sh start`. The D9 commit `445fe16` is the baseline,
outside this task.
Time: 2026-09-22T11:42Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_shared.lua:77` and `:85`: "writes nothing" cannot see a write
  of `cloud`.** The no-cloud-slot fixture seeds the active file with `cloud\n`.
  #28 then checks that the file still says `cloud\n`, so a switch that wrote
  `cloud` there leaves the file byte-identical.
  - One mutation keeps all 31 assertions green on a scratchpad copy: `switch()`
    calls `write_active(next)` *before* its no-cloud guard, then
    `if not shared.settings.cloud then shared.active = "local"; return nil end`.
    That is the natural "persist, then apply" reordering.
  - #26 (returns nil) and #27 (stays local) still hold, because only the file
    is wrong.

  Failure scenario, under that mutation:
  1. The user has a cloud slot and is deliberately on local, so the file says
     `local`.
  2. The cloud slot drops. For example, `allow_remote` is set to false for a
     while, or `cloud_base_url` gets a typo; Task 1 drops the slot with a
     warning.
  3. Out of habit they press Ctrl+Shift+B and see `云端未配置`. The file now
     says `cloud`.
  4. They restore the config and redeploy. The new Lua state starts on cloud,
     and every Enter sends the draft to the third party. They never chose
     cloud while a cloud slot was configured.

  That breaks acceptance item 3 ("writes nothing") and §7.2's "must be made
  deliberately by the user", with every test green. The current code is
  correct: `ime_translate_shared.lua:84-87` returns before any write. Only the
  lock is missing, and the gap is the plan's Step 1, copied verbatim.

  Fix: after #28, remove the file, switch again with no cloud slot, and assert
  `read(ACT) == nil`. Probed on the scratchpad: 32 green on the current code,
  and the mutation fails at the new assertion.

### 🟢 Suggestions
- **`rime/lua/ime_translate_shared.lua:50-52`: nothing locks the write and
  close checks. This is the surviving mutation, `return true`.** The only
  failed-write test (`tests/test_shared.lua:89-93`) fails at `io.open`, so
  `write_active` returns at `:49` and never reaches `:52`. Judged: it matters
  little.
  - **The check itself is right.** A stub `io.open` whose handle's `close`
    returns `nil, "No space left on device", 28` (a flush at close on a full
    disk) gives `remembered == false`. So does one whose `write` returns `nil`.
    In Lua 5.4.8, `close` on a regular file returns exactly `true`, so
    `closed == true` is sound.
  - **Scenario under the mutation.**
    - The disk is full and the user switches to cloud. `io.open(…, "w")`
      succeeds and truncates the file, the flush at close fails, and
      `switch()` reports remembered.
    - Task 4 then leaves out the "not remembered" log line §5.6 asks for.
    - The file is left empty, so the next Lua state starts on local. The
      failure goes toward privacy, and all it costs is one log line in a rare
      case.
  - **Cheap to lock, if wanted.** In the failed-write block, stub `io.open` for
    the active path with a handle whose `close` returns
    `nil, "No space left on device"`. Assert `remembered == false`, then
    restore `io.open`. `write_active` looks up `io.open` at call time, so the
    stub reaches it.

### What was walked
- **Plan against implementation.** No deviation:
  - `ime_translate_shared.lua` is byte-identical to Step 3 (diffed).
  - `tests/test_shared.lua` is byte-identical to Step 1.
  - The block appended to `tests/test_session.lua` (`:118-133`) is identical
    to Step 1's.
  - Every line of Step 4 is present in `session.lua`.
- **Step 2, re-run.** The baseline (`445fe16`) `shared.lua` and `session.lua`
  were run in a sandboxed HOME, with a fake `security` first on PATH. The
  baseline `ensure` reads the real `~/Library/Rime` and runs the real
  `security`, hence the sandbox. Both tests fail as the plan predicts:
  - `test_shared` at #1: `got "nil" want "local"`
  - `test_session` at #48: `got "  -> Today"`
- **Mutations**, on a scratchpad copy. The working tree was not touched;
  `diff -r` confirmed it after every run.
  - Red:
    - the caller's three: `read_active` ignoring `has_cloud` (#22), a failed
      open reported as remembered (#30), `clear` keeping the mark (#53)
    - whitespace stripping reduced to CR (#18)
    - the cloud key never read (#4)
    - `current()` ignoring `active` (#10)
    - `switch()` never writing (#9)
    - `read("*a")` for `read("*l")` (#16)
    - a switch that only goes to cloud (#12)
    - no trailing newline written (#9)
    - `ensure` never reading the active file (#16)
    - `set_result` not writing the mark (#48)
    - `set_result` only setting the mark, never resetting it (#49)
    - `set_error` only setting the mark, never resetting it (#52)
    - the error prompt unmarked (#51)
    - the result prompt unmarked (#48)
  - Survived:
    - `write_active` returning `true` (green 1)
    - a write before the no-cloud guard (yellow 1)
    - the no-cloud branch's `shared.active = "local"` removed. This one is
      equivalent: with no cloud slot, `ensure` has already set local, and
      `settings` does not change within a Lua state.
- **Dimension 4, as asked.**
  - **What `shared` holds:** `settings`, `warnings`, `api_key`, `cloud_key`,
    `active`, `loaded`, the two paths and `read_key`. Under §6.1's test, none of
    them needs to differ between input boxes. Settings and keys are read-only
    after `ensure`. `active` must be the same everywhere, which §5.6 and the
    rewritten §6.1 paragraph both state. **Sound.** No session-scoped value
    leaked into `shared`.
  - **The per-result marker stayed in the Context**, as `K_CLOUD`, and
    `prompt()` reads it from there, not from `shared.active`. That is what
    keeps the marker right. The processor's on-screen check
    (`ime_translate_processor.lua:139`) compares the segment's prompt with
    `session.prompt(ctx)`. Had the marker come from `shared.active`, a
    Ctrl+Shift+B in app A would change `session.prompt` for a result shown in
    app B:
    - B's Enter would see a mismatch and show the translation again instead of
      committing it
    - B's ☁ would name the active slot, not where the translation came from

    Neither happens here.
  - **`fresh()` is faithful.** It simulates a new Lua state by resetting only
    `loaded`, but `ensure` overwrites every field it sets, including
    `cloud_key`, which becomes nil when there is no slot.
  - **Evidence.** The cross-app claim rests on one Lua state per module init
    (F28, a source reading). Smoke row G5 measures it, and G6 measures that
    the slot is remembered (Task 6).
- **The tests and the real machine.** Every `tests/test_*.lua` was run under a
  wrapper that logs `io.open`, `io.popen` and `os.execute`.
  - `test_shared` opens only its two `os.tmpname()` files and
    `/nonexistent-ime-translate-dir/active`. It calls `popen` zero times.
  - No test in the suite opens a path under `$HOME/Library` or runs
    `security`.
  - The paths and the `read_key` stub are set (`tests/test_shared.lua:12-18`)
    before the first `ensure`.
- **Red lines 1-5.**
  - The diff has no `ctx:clear` and no `commit_text`; `session.clear` sets
    properties only.
  - `commit_translation` commits `session.text(ctx)`
    (`ime_translate_processor.lua:147`), which the marker never touches.
    ☁ exists only in the prompt, which `get_commit_text()` never reads (F9).
  - The diff adds no shell command, and `read_key`'s `json.shq` is unchanged.
  - D1 is closed.
- **Dimensions 7-9.**
  - ☁ is `E2 98 81` (U+2601, no VS16) both in `session.lua` and in §6.4. The
    result prompt is `  ☁ text` and the error prompt `  ☁ ✗ reason`, as §6.4
    has them.
  - No new engine claim. The test comment on `fresh()` cites F28.
  - Nothing is built beyond the plan; the menu-bar marker §7.2 leaves out is
    not built.
- **`read_active` edges.** Tests cover a missing file, an empty one, garbage,
  `Cloud`, and trailing spaces or CR. Only the first line is read. A directory
  or an unreadable file fails at `io.open` or `read` and gives local. Every
  failure lands on local.
- **Hard checks.** `checks_gate`, `checks_lua_invariants`, `checks_secrets` and
  `checks_language` are clean on all four files.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| lua tests/test_shared.lua and lua tests/test_session.lua pass every assertion | ok | `test_shared: 31 assertions OK`, `test_session: 54 assertions OK`; `scripts/run_tests.sh`: all 11 files PASS, `test_processor` 162 and `test_glue_load` unchanged |
| No active file, anything but cloud, or cloud with no cloud slot starts on local; cloud is remembered across a new Lua state | ok | #1, #19-#21, #22-#23, #16-#18 |
| switch() with no cloud slot returns nil, stays local and writes nothing; a failed write still switches and reports it | ok, partly locked by tests | #26-#28 and #29-#31. The code is correct. "Writes nothing" cannot see a write of `cloud` (yellow 1). "Reports it" is locked only for a failed open (green 1) |
| Both Keychain keys are read once, at ensure; the tests never touch ~/Library or run security | ok | #4, #5, #15 and #24. The io trace of every test file shows no `$HOME/Library` path and no `security` |
| A cloud result shows '  ☁ text', a cloud error '  ☁ ✗ reason'; clear drops the mark; callers passing no cloud flag are unchanged | ok | #48-#54. The processor's three-argument calls are unchanged, and `test_processor` passes all 162 |

### Verdict
0 red / 1 yellow / 1 green: no red, clear to close. Fix the yellow, or defer it
with a one-line reason recorded here.

### Resolution (implementer, after round 1)

- **Yellow, fixed.** After #28 the test removes the active file, switches
  with no cloud slot again, and asserts that no file exists (#29). A switch
  that writes before its no-cloud guard now fails at #29.
- **Green, taken.** A stubbed `io.open` gives a handle whose `close` fails
  as on a full disk. The switch still happens, and `remembered` is false
  (#33, #34). `return true` in `write_active` now fails at #34.
- `test_shared: 34 assertions OK`.

---

## Task 4: The processor switches and translates with the active slot — round 1

Range: `4d7ef4abd987ba6d31940a5e34ea83e7a18ff36a..HEAD` holds no commit of this
task. The work is uncommitted and was reviewed as `git diff 4d7ef4a` on its two
deliverables:
- `rime/lua/ime_translate_processor.lua`
- `tests/test_processor.lua`

Not reviewed: `docs/features/003-backend-switch/progress.json`, which is ledger
state written by `progress.sh` (Task 3 closed, Task 4 started).
Time: 2026-09-22T11:53Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- None.

### 🟢 Suggestions
- **`tests/test_processor.lua:607-613`: no test locks the switch out of an
  `error`, though it is the recovery path the design names.**
  - §5.2's key table gives the error column "same", and §5.6 voids "a
    translation or an error". The README text in Task 5's plan says: when the
    cloud fails, "Enter commits the Chinese, or `Ctrl+Shift+B` then Enter
    translates it locally".
  - Every switch in the tests starts from `idle` or `result`. The code is
    right: `ime_translate_processor.lua:218` clears whatever phase is set.
  - One mutation keeps all 195 green on a scratchpad copy: `:218` becomes
    `if session.phase(ctx) == "result" then session.clear(ctx) end`.

  Failure scenario, under that mutation:
  1. The cloud times out, and the prompt shows `  ☁ ✗ 翻译超时`.
  2. The user presses Ctrl+Shift+B to go local. The phase stays `error`, and
     `show` draws the same reason again.
  3. The next Enter takes `commit_draft`. The Chinese goes into the input box,
     not a local translation.

  Nothing is lost, but the one-key recovery §5.6 promises does not happen.

  **Lock, probed on the scratchpad.** Insert a block after the release block
  (`:627`), where the cloud slot is configured and local is active:
  1. A local error, then Ctrl+Shift+B. Assert that the prompt is `""`, the
     phase is `idle` and the slot is `cloud`.
  2. Enter. Assert that the same draft went out with `cloud_settings` and that
     the prompt is `  ☁ Today`.

  The current code passes it, and the mutation fails at the prompt assertion.
  The URL block after it is unaffected: its settings have no cloud slot, so
  `current()` returns local whatever `active` says. `:639` resets `active`.
  - **Same kind, lower value: the caret inside the input.** Adding
    `switch_backend` to `ACTS_ON_DRAFT` (`ime_translate_processor.lua:44-45`)
    also keeps 195 green.
    - Under it, the first Ctrl+Shift+B with the caret inside the pinyin only
      moves the caret and switches nothing.
    - With unselected pinyin the notice would not show anyway (the F29
      derivation), so the user believes they switched. The next translation
      comes from the old slot, and only the ☁, or its absence, says so.
    - A probe catches it: the caret at 3 in `jintianyoudianlei`, a switch,
      then assert `caret_pos == 3` and that the slot changed.

### What was walked
- **Plan against implementation.** No deviation.
  - Every code block of Step 3 appears verbatim in the processor.
  - The appended test block is byte-identical to Step 1.
- **Step 2, re-run.** The new test was run against the baseline processor
  (`4d7ef4a`). It fails at #163, `ctrl+shift+B is taken: got "2" want "1"`,
  as the plan predicts.
- **Mutations**, on a scratchpad copy. The working tree was not touched;
  `diff -q` confirmed it after every run.
  - Red:
    - the caller's four: no void (#172), the marker by slot name (#195),
      translating with `S.settings` (#181), the notice only turned on (#164)
    - void without `show` (#172)
    - `show` without `session.clear` (#172)
    - the notice turned off, then on (#164)
    - no notice (#164)
    - the local and cloud notices swapped (#175)
    - no cloud slot showing the local notice (#164)
    - `S.switch()` not called (#164)
    - the switch returning kNoop (#163)
    - the switch committing the draft (#166)
    - the switch calling `ctx:clear()` (the fake's red-line assertion)
    - the local key sent with the cloud settings (#182)
    - the marker never set (#183), always set (#6), inverted (#6), or taken
      from the local slot's URL (#183)
    - the marker left off errors (#186), or off results (#183)
    - the release acted on (#46)
  - Survived: the void only in `result`, and `switch_backend` in
    `ACTS_ON_DRAFT` (green 1).
- **Every path of the switch branch.** Each was walked in the code, and each
  not covered by the tests was driven through the fake on a scratchpad copy:
  four probes, 25 assertions, all green on the current code.
  - **Idle, no draft.** `show` skips because `draft == ""`, so `back()` is
    never touched. With no input there is nothing composing, so there is
    nothing for `set_option` to refresh (F20).
  - **Idle, unselected pinyin.** The trace holds only the two notice calls:
    no confirm, no `clear_non_confirmed`.
  - **Result.** #171-#185.
  - **Error.** Probe P1: voided, `idle`, switched. The next Enter translates
    the same draft with the other slot, marked.
  - **A stale result, check 2 first.** The draft was changed with no key
    event. Probe P2:
    - Check 2 clears the phase at `:78-80`, and `decide` sees `idle`.
    - The switch commits nothing, and the text property is `""`.
    - The next Enter sends the new draft to the backend. The old English
      cannot be committed.
  - **The caret inside the input.** Probe P3: the switch acts at once, with
    the caret and the input untouched. Leaving `switch_backend` out of
    `ACTS_ON_DRAFT` is right: the switch does not act on the draft, so F15's
    truncation does not reach it.
  - **The release.** #193-#194.
- **Red lines 1-3.**
  1. The branch has no `commit_text` and no `ctx:clear()`, and
     `session.clear` writes properties only. The translate branch gains no
     path to a clear.
  2. The ☁ exists only in the prompt, which `get_commit_text()` never reads
     (F9).
     - `commit_translation` commits `session.text(ctx)`. #185 commits
       `A bit tired today`, with no marker.
     - The on-screen check at `:152` compares against `session.prompt(ctx)`,
       which reads the marker from the Context. So the second Enter commits a
       marked translation (#184-#185).
  3. After a switch the phase is `idle`, and text, snapshot and marker are all
     `""`. The next Enter in this session can only translate, lock or commit
     the draft; it can never commit a translation.
     - Checks 1 and 2 are unchanged.
     - Another session's result stays valid across a switch. Its draft did
       not change, and its ☁ comes from its own Context (the Task 3 review).
- **`set_option` twice inside a key event (the caller's question).** The fake
  only records the calls, and a fake cannot show what the engine then does.
  The points below are derivations from F8, F20 and F29, not measurements.
  - **What each call does.** It fires `OnOptionUpdate`. While composing, the
    engine pops every trailing segment below `kSelected`, pushes a fresh empty
    one and recomposes. Input and caret are not touched, and selected and
    confirmed segments survive.
  - **The prompt.**
    - `show` has written `""` before either call, and `idle`'s prompt is
      `""`.
    - A rebuilt segment starts with an empty prompt, so the refresh can only
      remove what is already gone. It cannot bring a translation back, and
      the order of `show` and the calls does not matter.
  - **The draft.**
    - **Result or error, Chinese mode.** Translate is reached only with
      nothing unselected (`:118-121`), so every segment is selected. Only the
      trailing empty segment is rebuilt, and the draft stays byte for byte
      the same.
    - **English mode.** The open `raw` segment is rebuilt as `raw` again
      (F19).
    - **Idle with unselected pinyin.** The open segment is recomposed under
      options no component reads: `rime/` and the schema read none of the
      three notice names. Its candidates are the same, but **a highlight
      moved by hand falls back to the default**. This is the one gap between
      the fake and the engine.
      - It is already a recorded derivation: `decisions.md`, "Design review
        before feature 003 Task 1", "The switch refreshes an open segment".
        Task 6's R2 measures it.
      - It shows before any Enter, and the phase is `idle`.
      - Enter with unselected pinyin runs `lock_literal`, which locks the
        letters, so nothing unseen is committed.
  - **Twice.** The second refresh repeats the first on an unchanged
    composition. It costs two recompositions of the open or trailing segment
    per switch; not measured.
  - **Precedent.** The Shift tap calls `set_option("ascii_mode")` from inside
    a key event with a draft open (`:105`), which the 2026-09-21 spike ran
    (F19-F20 in the verification table).
    - There the option changes what the segment reads, which is why the tap
      confirms first.
    - Here the options change nothing any component reads.
  - **The translate branch's comment** (`:139-140`: no refresh after the
    prompt is written) still holds. The only refresh this task adds runs after
    the prompt is already `""`.
- **The tests and the real machine.**
  - `shared.loaded = true` at `:21`, so `ensure` never reads
    `~/Library/Rime`.
  - `active_path` is an `os.tmpname()` from `:561`, before the first
    Ctrl+Shift+B at `:574`. No earlier test presses B with Control and Shift.
  - Run with `HOME` set to an empty scratch directory, the test created no
    file under it.
  - After the full suite, `~/Library/Rime/ime_translate.active` does not
    exist.
  - A wrapped `os.tmpname` shows that the temp file is removed at the end.
- **Dimensions 4-5 and 7-9.**
  - `NOTICE` is a constant table. The active slot is process-wide, which
    §5.6 and §6.1's test both require. The per-result marker stays in the
    Context.
  - No shell command is added. The active file is written with `io.open`
    (Task 3).
  - The three notice names match Task 5's schema block and the check script
    in its plan.
  - The log names the slot on every translation and every switch (§7.2, row
    R4), and no key reaches it.
  - The new upstream claims in comments cite F20 and F29. D1 is closed, and
    no decision is open.
  - Nothing is built beyond the plan.
- **Hard checks.** `checks_gate`, `checks_lua_invariants`, `checks_secrets`
  and `checks_language` are clean on both files.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| lua tests/test_processor.lua passes every assertion, and scripts/run_tests.sh passes | ok | `test_processor: 195 assertions OK`; `scripts/run_tests.sh`: all 11 files PASS |
| The switch commits nothing, keeps the draft, and voids a translation on screen; the next Enter translates the same draft with the other slot's settings and key | ok | Nothing committed: #166, #177, #192. The draft: #167, #178. Voided: #172-#173. Same draft, cloud settings and key: #180-#182, local before it #168-#169. The switch out of `error` holds in probe P1 but no test locks it (green 1) |
| Each outcome turns its notice switch on then off: local, cloud, no cloud slot | ok | #164, #175, #190, as exact traces. Off-then-on and on-only are both red |
| The marker follows the URL: a local slot pointed at a remote URL is marked | ok | #195. #170: loopback unmarked. #183 and #186: a cloud result and a cloud error marked |
| The tests write the active file only to a temporary path | ok | "The tests and the real machine" above: a sandboxed `HOME`, the real path absent after the suite, the temp file removed |

### Verdict
0 red / 0 yellow / 1 green: no red, clear to close.

### Resolution (implementer, after round 1)

- **Green 1, taken, both locks.**
  - **From an error.** A local error, then `Ctrl+Shift+B`: the prompt goes,
    the phase is idle, and the slot is cloud. The next Enter translates the
    same draft with the cloud slot and shows `  ☁ Today`; nothing is
    committed. Clearing only in `result` now fails at #197.
  - **The caret inside the input.** The switch happens at once and the caret
    stays at 3. Adding `switch_backend` to `ACTS_ON_DRAFT` now fails at #205.
- `test_processor: 207 assertions OK`.

---

## Task 5: Schema notices, template, README — round 1

Range: `b95be0edc432d9c254945f2d064266bf893f2dc9..HEAD` holds no commit of this
task. The work is uncommitted and was reviewed as `git diff b95be0e` on its
three deliverables:
- `rime/luna_pinyin_translate.schema.yaml`
- `rime/ime_translate.yaml`
- `README.md`

Not reviewed: `docs/features/003-backend-switch/progress.json`, which is ledger
state written by `progress.sh` (Task 4 closed, Task 5 started). No Lua file and
no test changed since the baseline (`git diff --quiet b95be0e -- rime/lua tests`).
Time: 2026-09-22T12:06Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`README.md:98-100`: "Every key from `backend` to `prompt`" covers the
  whole table above it, shared keys included.**
  - The table (`README.md:87-96`) runs `backend`, `base_url`, `model`,
    `timeout_ms`, `max_chars`, `max_tokens`, `allow_remote`,
    `api_key_account`, `debug_log`, `prompt`. So the rule names all ten, and
    the next sentence then calls three of them shared.
  - `config.lua:34-36` gives a twin to eight keys only.
  - Failure scenario, probed through `config.load`:
    1. The user wants a lower limit for the paid cloud and adds
       `cloud_max_chars: 500`. `config.lua:123-124` warns
       `unknown config key: cloud_max_chars`, which only `debug_log` shows.
       Every cloud request can still carry 2000 characters.
    2. Or the user writes `cloud_allow_remote: true` in place of
       `allow_remote: true`. The slot is dropped
       (`non-loopback base_url needs allow_remote: true`), and every
       Ctrl+Shift+B shows `云端未配置`.
  - Fix: name the keys: `backend`, `base_url`, `model`, `prompt`,
    `timeout_ms`, `max_tokens`, `api_key_account` (and `temperature`, which
    the table does not list).
  - The text is the plan's own (Task 5, Step 3, "Configure"). It is a defect
    in the plan, not a deviation by the implementer.
- **`README.md:179-181`: in the section this task rewrote, the freeze bound
  still names `timeout_ms`.**
  - Before 003 the LLM was the only backend, and `timeout_ms` was its bound.
    Now the cloud reads `cloud_timeout_ms`. An unset one is 1500, not the
    local value (`config.lua:168-171`, backend.md §9).
  - The README never says that an unset `cloud_` key takes the default. Only
    the template does (`rime/ime_translate.yaml:45-46`).
  - Failure scenario, probed:
    1. The user has no `cloud_timeout_ms`, and GLM keeps answering
       `☁ ✗ 翻译超时`.
    2. The README says to tune `timeout_ms`, so the user sets
       `timeout_ms: 2500`.
    3. The cloud stays at 1500 (probe: local 2500, cloud 1500), and the
       timeouts go on. Meanwhile the local `translate` slot's worst-case freeze
       has gone up to 2500 for nothing.
  - Fix: write `cloud_timeout_ms` in that bullet, and add one sentence to the
    Configure paragraph saying that an unset `cloud_` key takes the default.

### 🟢 Suggestions
- **`README.md:170-171`: "With no cloud backend configured, the notice says
  `云端未配置` and nothing changes."** Two cases do not match it.
  - **(a) A dropped slot.** `config.lua:174-176` drops a configured cloud slot
    for several reasons: no `allow_remote`, an `http://` remote, an unknown
    `cloud_backend`, or D9's missing `cloud_base_url`. Each also shows
    `云端未配置`.
    - Scenario: the user follows step 2 but leaves out `allow_remote: true`.
      The README then says there is "no cloud backend configured".
    - Nothing points to the reason. Only the log names it (`cloud slot
      dropped: …`, with `debug_log: true`).
  - **(b) "Nothing changes."** `ime_translate_processor.lua:218-219` voids a
    translation on screen before `S.switch()`.
    - Scenario: the English is showing and there is no cloud slot. After
      Ctrl+Shift+B the English is gone, and the next Enter translates locally
      again.
    - This is what §5.6 asks for. The sentence is what overstates it.
  - Suggested wording: "With no cloud backend, or one the config refused (see
    The log), the notice says `云端未配置` and the backend stays local."
- **`README.md:158-159`: step 3 assumes that local is active.**
  - "Press `Ctrl+Shift+B`. The notice says `云端翻译`" is only true when the
    IME starts on local.
  - After "remove the cloud for good" (`README.md:188-189`), `read_active`
    returns local, but the file keeps `cloud`
    (`ime_translate_shared.lua:39-45`). A switch with no cloud slot writes
    nothing (`:84-87`).
  - Re-adding the cloud lines and redeploying therefore starts on cloud. Step
    3's press then switches to local and shows `本地翻译`.
  - Suggested wording: "press `Ctrl+Shift+B` until the notice says
    `云端翻译`", as "Back to `translate`" already says.
- **`README.md:132-134, 187-189`: nothing covers a setup made by the previous
  README.**
  - That README put the LLM in the unprefixed keys. This machine's
    `~/Library/Rime/ime_translate.yaml` has that shape: key names read,
    `backend: openai` with the GLM `base_url`, unprefixed. `install.sh` never
    replaces an existing file (`README.md:28-30`).
  - With that file:
    - the local slot is GLM. The ☁ shows, so nothing is hidden.
    - there is no cloud slot.
    - "Press `Ctrl+Shift+B` until the notice says `本地翻译`" never ends:
      every press shows `云端未配置`.
  - Task 6 Step 1 migrates this machine's file with the user's yes, so the
    live case is covered.
  - The README still lacks one sentence: an LLM set up before this version
    sits in the unprefixed keys; give them the `cloud_` prefix and put the
    local slot back to `translate`, or delete them.
- **`rime/ime_translate.yaml:38-39`: "Its translations show a ☁" ties the
  marker to the slot.**
  - The marker is decided by the URL (`ime_translate_processor.lua:136`, and
    §5.6: "decided by the URL, not the slot name").
  - Scenario: a cloud slot pointed at a loopback model, such as the apfel-local
    case §7.4 lists under the openai adapter, with
    `cloud_base_url: http://127.0.0.1:11434/v1`.
    - After `云端翻译`, it shows `  -> …`.
    - The user takes the missing ☁ to mean that the switch failed.
  - `README.md:166` gets it right ("from a cloud server"). Suggested wording
    for the template: "Translations from a non-local server show a ☁."
- **`rime/luna_pinyin_translate.schema.yaml:28-29`, and the reason recorded
  behind it: the abbrev is right to keep, but Squirrel 1.1.2 is not why.**
  - The reason is recorded in `decisions.md:943-946` and in the Task 5 plan,
    lines 14-18.
  - **What librime returns.** The short label is a slice as long as the first
    character (`switches.cc:153-154`).
  - **What Squirrel reads.** Squirrel 1.1.2's `notificationHandler`, in its
    `option` branch, turns both slices into strings with `String(cString:)`.
    That ignores `length` and reads to the NUL.
  - So without `abbrev` the short label would still be the whole `云端翻译`.
    (Source reading. The scratchpad copies are byte-identical to tag 1.1.2,
    fetched from GitHub.)
  - The F29 row itself says nothing about `abbrev`.
  - Scenario: Task 6's G1 ("each in full") passes with or without the abbrev.
    If its pass is read as proof that the abbrev was needed, the evidence
    record says something the source contradicts.
  - Suggestion: a `/design-review` note to F29 and `decisions.md` saying the
    abbrev is defensive, for any frontend that honours the length. No change
    to the schema.

### Deviations from the plan, judged
- `rime/ime_translate.yaml:37` ("off until `cloud_backend` and
  `cloud_base_url` are set"), `:42` ("required;") and `README.md:145` ("both
  required"): **an improvement.**
  - D9 closed after the plan was written (`decisions.md:957-971`).
  - The plan's "off until `cloud_backend` is set" would contradict
    `config.lua:174`.
- `README.md:119`, `cloud_api_key_account` in step 1: **an improvement.** The
  plan says nothing about step 1, and step 2's block now names
  `cloud_api_key_account`. Leaving the old name would send the user to the
  wrong key.
- `README.md:184-185`, `☁ ✗ 密钥无效` and `cloud_api_key_account`: **an
  improvement.**
  - The plan says nothing about this paragraph.
  - A 401 or 403 (`backend.lua:156`) from the GLM cloud slot renders as
    `  ☁ ✗ 密钥无效` (`session.lua:88`, `state.lua:19`). The old string never
    appears for the setup the README describes.
- `README.md:170`, "no cloud backend" where the plan says "no cloud slot":
  wording only.
- Everything else matches the plan's text, including the schema block, the
  header comment 10 and the description line.

### What was walked
- **Notice names.** The plan's loop gives three `ok` lines. Each name is
  declared exactly once, and they match `NOTICE`
  (`ime_translate_processor.lua:18-20`).
  - The loop can fail: on a scratchpad copy with `no_cloud` renamed, it prints
    `MISSING ime_translate_notice_no_cloud`.
- **Upstream, re-read for the switch block** (librime 1.16.0 on the
  scratchpad; Squirrel sources byte-identical to tag 1.1.2).
  - `switches.cc:138-160`: `GetStateLabel`, with its `abbrev` branch.
  - `switches.h:21`: a label is true only when it has a pointer and a
    non-zero length.
  - `switch_translator.cc:33-36, 216, 245`: the menu, and the folded menu,
    both skip a switch whose label is empty.
  - `config_data.cc:252-258`: Null becomes nullptr, and a Scalar becomes a
    `ConfigValue`.
  - yaml-cpp 0.8.0 `singledocparser.cpp:96-108`: a quoted `""` is a
    `NON_PLAIN_SCALAR`, so it becomes `OnScalar("")`, not null.
  - `rime_api_impl.h:1103-1116`.
  - Squirrel `notificationHandler` / `showStatusMessage`,
    `SquirrelPanel.updateStatus` (`.mix`: the short label if non-empty, else
    the long one), and `SquirrelTheme.swift:78` (the default is `.mix`).
  - Conclusions:
    - State 0 has no label, so all three switches stay out of the menu and
      the folded menu.
    - On gives the full label, both long and short.
    - Off gives two empty labels, so `showStatusMessage` is skipped and the
      on label stands.
- **The YAML.** Ruby Psych parses the schema. Diffed key by key against
  `b95be0e`:
  - only `schema.description` and `switches` differ.
  - Within `schema`, only `description` differs, and it gains exactly one
    line.
  - The first four switches are identical.
  - `engine`, `key_binder`, `ascii_composer`, `recognizer`, `punctuator`
    and the rest are unchanged.
- **Every user-facing claim, against the code.** A `config.load` probe on the
  scratchpad, ten inputs:
  - the template as shipped: no warnings and no cloud slot.
  - the template with its cloud lines uncommented, README step 2, and the
    Anthropic example: each gives the expected slot.
  - step 2 without `allow_remote`: the slot is dropped.
  - `cloud_allow_remote` and `cloud_max_chars`: unknown keys.
  - `timeout_ms` raised: the cloud stays at 1500.
  - D9: the slot is dropped.
  - the live pre-003 shape: the local slot is GLM, with no cloud slot.
  - Also checked in the code:
    - sharing: `config.lua:168-169`.
    - defaults, not the local slot's values: `:168`.
    - the ☁ decided by the URL: `ime_translate_processor.lua:136`,
      `session.lua:86-88`.
    - no fallback: one backend call per Enter, none in `backend.lua`, and
      Enter in `error` commits the draft (`decide.lua`).
    - remembered: `ime_translate_shared.lua:47-53, 66, 83-89`.
    - `ime_translate.active` sits next to the config (`:15-16`), which is the
      file the uninstall line removes.
- **Language.** `checks_language` is clean on all three files.
  - The README's Chinese is all in backticks.
  - The template holds no CJK.
  - The schema is a data file.
- **Red lines 1-5 and dimension 7.** Not applicable: this task changes no Lua
  and no test.
  - What the schema adds is read only by Squirrel's notice path and the
    switcher. The processor only sets the options.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every notice switch the processor names is declared, with an empty first state and an abbrev equal to its states | ok | The plan's loop gives three `ok` lines, and a renamed copy gives `MISSING`. Psych dump: `states == abbrev == ["", label]` for each of the three |
| The template and the README show the cloud_ keys, Ctrl+Shift+B, the ☁ marker and the no-fallback rule | ok | Template `:15-19, :37-49`. README `:49, :98-100, :104-112, :132-171`. The no-fallback rule is at README `:168-169`. `grep -c cloud_`: README 15, template 10. Yellow 1 and 2 concern the accuracy of two sentences, not whether the content is there |
| scripts/run_tests.sh and the hook tests pass | ok | `scripts/run_tests.sh` rc 0, all 11 files PASS. `run-hook-tests.sh` 73 passed, 0 failed. `run-githook-tests.sh` 25 passed, 0 failed |

### Verdict
0 red / 2 yellow / 5 green: no red, clear to close. The two yellows should be
fixed, or deferred with a reason, before the commit.

### Resolution (implementer, after round 1)

- **Yellow 1, fixed.** The Configure note names the eight keys with a
  `cloud_` copy, and says that an unset one takes the default, not its local
  twin's value. It also says that `allow_remote`, `max_chars` and `debug_log`
  have no copy.
- **Yellow 2, fixed.** The Speed cost names `cloud_timeout_ms`, and its
  default 1500, instead of the local `timeout_ms`.
- **Green 1, taken.** The no-cloud bullet now says three things:
  - the translation on screen goes
  - a refused cloud slot counts as none, and why it is refused
  - `debug_log` names the key
- **Green 2, taken.** Step 3 says to press until `云端翻译` shows.
- **Green 3, taken.** Step 3 has a note on upgrading from a single backend:
  add `cloud_` to the model lines.
- **Green 4, taken.** The template says a translation from a non-loopback
  server shows ☁, not the slot's translations.
- **Green 5, taken as a design correction.** F29 and the "Design review
  before feature 003 Task 1" entry now note that Squirrel 1.1.2 shows the
  whole label even without `abbrev`. The schema keeps `abbrev`.
