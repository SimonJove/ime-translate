# Review log

Every task is reviewed by `task-reviewer` before it is marked done. Task 5 is
manual; its record is `docs/smoke-report-005.md`.

---

## Task 1: cloud_timeout_ms capped at 2000 — round 1

Range: `ba2f6ed..` working tree, limited to
`rime/lua/ime_translate/config.lua` and `tests/test_config.lua` (uncommitted;
backend.lua, state.lua, test_backend.lua belong to Task 2 and were not reviewed)
Time: 2026-09-23 15:46 UTC

### 🔴 Must fix
- None.

### 🟡 Should fix
- None.

### 🟢 Suggestions
- `rime/lua/ime_translate/config.lua:193` — the cloud cap's reason reads
  "leaves the local fallback no time". With `cloud_timeout_ms: 2200` the user
  sees `cloud_timeout_ms above 2000 leaves the local fallback no time; capped at
  2000`, but 2200 would leave it 300 ms, not none. Something like "would push
  the freeze past 2500 with the local fallback" states the actual reason (§8.2).
  Advisory: the value is capped either way.

### What was walked
- Dimensions 1–5 (never eat text, one commit exit, invalidation checks, session
  state, shell escaping): the diff touches none of these paths. It changes only
  config-load bounding; no `ctx:clear()`, `commit_text`, Context state or shell
  string is involved. `CLOUD_TIMEOUT_MAX` is a module constant, i.e. read-only
  process-wide config, which is correct under dimension 4.
- Dimension 7, constants against design §8.2 / §9: local cap 2500, floor
  500, reset-to-default 1500, and cloud cap 2000 all match. The local warning
  text is the same string as before (`timeout_ms above 2500 can lose the draft;
  capped at 2500`), so nothing that matched the old warning is broken.
- Dimension 6, can the tests fail: proved by mutation in a scratch copy (repo
  untouched). Setting `CLOUD_TIMEOUT_MAX` back to 2500 fails assertion #122
  (`got "2500" want "2000"`). Passing `CLOUD_TIMEOUT_MAX` to the local
  `timeout_ms` call fails assertion #22 (`got "2000" want "2500"`). The
  unmutated tree passes 144 assertions.
- Dimension 9, plan deviations: `bound_timeout` takes the ceiling as the plan
  says, plus a `why` argument so each slot's warning names its own reason; this
  is an improvement, not an omission (the old single message would call the
  cloud cap "can lose the draft", which is not why it is 2000). The plan's
  "`cloud_timeout_ms: 400` resets" case is covered by the pre-existing
  `cloud_timeout_ms: 99` assertion (same branch, below 500), not a new 400 row;
  equivalent.
- Stale references outside scope: `rime/ime_translate.yaml:48` and
  `README.md:153` still show `cloud_timeout_ms: 2500`. Task 5's plan lists
  both files ("Template: `cloud_timeout_ms` at most 2000"), so not a Task 1
  finding. `backend.lua:122`'s "[500, 2500]" is still true for either slot.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | every file PASS, exit 0 |
| cloud_timeout_ms above 2000 loads as 2000 with a warning; below 500 resets to 1500 | ok | 2500 and 99999 load as 2000, one warning naming `cloud_timeout_ms` and 2000; 2000 kept, no warning; 99 resets to 1500 with one warning |
| timeout_ms keeps its cap of 2500 | ok | `timeout_ms: 2500` with a cloud slot stays 2500; mutation lowering it fails #22 |

### Verdict
0 red / 0 yellow / 1 green — no red, clear to close
