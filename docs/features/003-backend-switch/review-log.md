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
