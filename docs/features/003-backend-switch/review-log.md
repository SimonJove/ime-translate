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
