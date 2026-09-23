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

---

## Task 2: The URL guard in the libretranslate adapter — round 1

Range: `ba2f6ed..` working tree, limited to
`rime/lua/ime_translate/backend.lua`, `rime/lua/ime_translate/state.lua`,
`tests/test_backend.lua`, `tests/test_state.lua` (uncommitted)
Time: 2026-09-23 15:48 UTC

### 🔴 Must fix
- None.

### 🟡 Should fix
- `rime/lua/ime_translate/backend.lua:67` with `:79` — `guard` puts the
  placeholder straight after whatever precedes the URL, but `unguard` only
  counts an `X_n` that starts at a `%f[%w]` frontier. So a URL glued to a
  preceding ASCII letter or digit can never come back. Trigger: draft
  `seehttps://a.com 看看` → sent `seeX_1 看看`. If `translate` keeps the
  token as it is, the output holds `seeX_1`, `unguard` counts 0 and the
  translation fails as `bad_guard` every time for that input (reproduced:
  `backend.unguard(backend.guard("seehttps://a.com 看看"))` is `nil`). Before
  the guard, the same draft would have translated. The draft is kept, so no
  text is lost. The same frontier also turns any `translate` output that glues
  the placeholder to the word before it (`inX_1`, the gluing §7.5 reports for
  raw URLs) into a hard failure rather than a restore. Fix by keeping the
  placeholder on a frontier when it is sent: pad it with a space when the
  preceding byte is `%w`, or leave such a draft unguarded. Add a test row for
  it.

### 🟢 Suggestions
- `tests/test_backend.lua:277` — the translate-level check that the request
  carries `X_1` does a substring match on the whole curl command line. A `q`
  that held only `X_1`, with the Chinese dropped, would pass here. The direct
  `guard` rows catch that today, but decoding the `-d` body and comparing `q`
  to `看一下 X_1 这个仓库` would make this row stand on its own.

### What was walked
- Dimension 1 (never eat text): `bad_guard` is an ordinary `(false, code)`
  return. `rime/lua/ime_translate_processor.lua:163-167` sends every `not ok`
  to `session.set_error` and never clears the context there, so a failed
  guard keeps the draft on screen. `finish` never raises: `unguard` does only
  string ops on a string that has already passed the `trim(out) == ""` check.
- Dimensions 2–5: the diff touches no `commit_text`, candidate, invalidation
  check or Context state. `guard`/`unguard` are pure functions; the URL list
  goes through a local (`guard`) inside `translate` and is not stored in the
  module. The URL reaches the shell only inside the JSON body, which is still
  quoted by `json.shq` (line 210). No new shell string.
- Dimension 6 (can the tests fail): proved by mutation in a scratch copy (repo
  untouched). Every one of 12 mutants went red. They dropped the
  existing-placeholder check, the leading frontier, the trailing frontier, the
  doubled-placeholder check (`~= 1` → `< 1`), the `)` strip and the `,;:!?'`
  strip; they sent `text` instead of `sent`; they skipped `prepare` and the
  `bad_guard` return; they used a string replacement in `gsub` (the `%1` URL
  row catches this); they made the URL match lazy; and they accepted only
  `https`. The unmutated tree: `test_backend` 160 assertions, `test_state` 18.
  The openai/anthropic rows assert that the URL is present and `X_1` absent,
  so guarding them would go red.
- Dimension 7: `bad_guard` maps to `✗ 翻译失败`, as §7.5 says, and the
  message table and the fallback agree. Checked `too_long`: it still counts
  the draft as typed, before the guard, which is correct because the user's
  limit concerns what they typed.
- Edge cases probed directly: `https://` with nothing after it is left alone;
  `https://a.com/X_2 和 …` is sent unguarded (pre-check); a draft holding
  `aX_1` is guarded, and its literal `aX_1` survives `unguard` untouched
  (the frontier is consistent between `guard`'s pre-check and `unguard`);
  percent-encoded URLs come back byte-exact; `X_12` does not count as `X_1`.
  A URL followed by an ASCII `,` and English (`https://a.com,see`) takes
  `,see` into the URL, because `,` is an RFC 3986 sub-delim. It is restored as
  typed and just left untranslated, so it is not a finding.
- Dimension 8: the claims about the `translate` service (it glues URLs and
  keeps `X_n`) point to §7.5, which labels them agent-observed. The loopback
  runs the caller reported are agent-observed, not measured.
- Dimension 9, plan deviations: `url_end` also strips a trailing `)` that
  closes nothing inside the URL, and keeps balanced parentheses. The plan
  lists only `.,;:!?'"`. The code comment explains it and a test row covers
  it. This is an improvement: `(https://b.com)` would otherwise send `(X_1`
  and restore a URL ending in `)`. The plan's `"` is not needed because `"`
  is not in `URL_CHARS`. `prepare`/`finish` match the plan's interface.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok for this task's files; runner currently not green | `test_backend` and `test_state` PASS and every tracked file passes. The runner also picks up untracked `tests/test_cache.lua` and `tests/test_route.lua` (Task 3, in progress, modules not yet written), which FAIL on `require`. Re-run once those are resolved before closing |
| The libretranslate request carries X_n in place of each URL, and the result carries the URLs as typed | ok | test_backend rows at 273-277. Mutants sending `text`, or skipping `prepare`, go red |
| A placeholder missing or doubled fails with bad_guard; the draft stays | ok | `unguard` rows for missing and doubled; translate row at 278-279; processor error path keeps the draft (`set_error`) |
| The openai and anthropic requests are unchanged | ok | rows at 281-284 assert the URL is present and `X_1` absent; no `prepare` on those adapters |

### Verdict
0 red / 1 yellow / 1 green. No red, so the task may close once the yellow is
fixed or deferred with a reason, and `scripts/run_tests.sh` is green.

## Task 3: The cache and the route, with the cloud-to-local fallback — round 1

Range: uncommitted work on `5c2b84f` — new `rime/lua/ime_translate/cache.lua`,
`rime/lua/ime_translate/route.lua`, `tests/test_cache.lua`,
`tests/test_route.lua`; `git diff HEAD -- rime/lua/ime_translate_shared.lua
tests/test_shared.lua tests/test_glue_load.lua`. backend.lua and state.lua
(Task 2) read for context only.
Time: 2026-09-23T15:50Z

### 🔴 Must fix
None.

### 🟡 Should fix
- `tests/test_route.lua:70-80` — nothing asserts which key the fallback
  request carries. Mutating `route.lua:40` from `S.api_key` to `S.cloud_key`
  leaves `test_route` green (checked in a scratch copy). Failure scenario: a
  later edit makes the fallback pass the active slot's key (an easy slip,
  since `S.current()` just returned the cloud key); the local slot is an
  `openai` adapter at a loopback server or, with `allow_remote`, a LAN or
  third-party host, and every cloud failure then ships the cloud API key in
  an `Authorization` header to that server, with the suite still green. The
  plan names "the local key" in the interface; the cloud path has its
  assertion (line 68), the fallback has none. Add
  `calls[2].cmd:find("LOCAL-KEY")` and the absence of `CLOUD-KEY`.

### 🟢 Suggestions
- `tests/test_cache.lua:18-20` — the separator row cannot fail: without the
  length prefix, `"a" .. "b\0c"` and `"a\0b" .. "c"` are still different
  strings (mutant stays green). Harmless in practice (the only slots are
  `local` and `cloud`, neither a prefix of the other), but the row does not
  test what its comment says; a pair such as slot `"ab"`/draft `"c"` versus
  slot `"a"`/draft `"bc"` would.
- `route.lua:34` — the `too_long` guard is behaviourally redundant: with
  `max_chars` shared, the local `backend.translate` also returns `too_long`
  before any request, so dropping the guard leaves `test_route` green and no
  observable changes. Fine to keep as a statement of §8.1; just know the
  row at `test_route.lua:104-107` does not pin it.
- `ime_translate_shared.lua:2` — the reflowed header line runs past the
  width of the rest of the comment.

### Paths walked and what was verified
- Dimension 1/2 (never eat text, one commit exit): route and cache call no
  `commit_text`, no `ctx:clear()`, touch no Context; route returns a table
  and never raises past `backend.translate`'s pcall. Nothing to walk until
  Task 4 wires it.
- Dimension 4 (§6.1): `route` keeps only the constant `FALLBACK_MS`; the
  cache is keyed by slot and draft only, which passes §6.1's test as amended
  in ba2f6ed. `test_glue_load` asserts no cache before `ensure()` and no
  session fields on the singleton. Mutating `ensure` to rebuild each call
  turns `test_shared` red.
- Dimension 5: no new shell construction; the fallback goes through
  `backend.translate`, which quotes via `json.shq`.
- Invariants from the brief: a local failure never reaches the cloud
  (`slot ~= "cloud"` returns first; row 52-57). Worst-case freeze: config
  caps `cloud_timeout_ms` at 2000 (`config.lua:192`), the fallback copies the
  local settings and sets 500 (`--max-time 0.500` asserted at row 78) without
  mutating `S.settings` (row 80); the local slot's floor of 500 cannot shrink
  it. Errors are never cached (`if ok then put`; mutant goes red). The
  fallback's answer is cached under `local`, not `cloud` (rows 81-87).
  `max_chars` is not a slot key (`config.lua:33`), so the too_long reasoning
  holds.
- Dimension 6, mutants run in a scratch copy: caching errors, fallback
  timeout 2500, returning the local code on a double failure, the fallback's
  `cloud` flag, skipping the cache read, `get` not refreshing, an off-by-one
  capacity, `ensure` rebuilding — all red. Green: fallback key (the yellow),
  the length prefix and the too_long guard (the greens).
- Dimension 7: `FALLBACK_MS` 500 and cache size 32 match §8.2/§8.3; the
  failed-both case returns the cloud's code and `fallback = false` per §8.1.
- Dimension 8: "a redeploy empties it" (`shared.lua:68`) is backed by F28.
- Dimension 9: matches the plan's interface and step list. The extra row
  "cloud failure with a cached local answer makes no local request" is an
  improvement consistent with plan step 4 ("a cache hit, or …"). No
  pre-translation code.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | all 13 files PASS; test_route 45, test_cache 17, test_shared 36 |
| A failed cloud request is followed by one local request with a 500 ms timeout; its success is marked fallback | ok | rows 70-80; mutants on timeout and flag go red |
| A local failure is never sent to the cloud; too_long never falls back | ok | rows 52-57, 104-107 (too_long holds by construction, see green) |
| A cached slot and draft make no request; errors are never cached | ok | rows 42-50, 58-60; mutants red |

### Verdict
0 red / 1 yellow / 3 green — no red, clear to close once the yellow is fixed
or deferred with a reason.

---

## Task 2: The URL guard in the libretranslate adapter — round 2

Range: `HEAD` (5c2b84f) working tree, limited to
`rime/lua/ime_translate/backend.lua`, `rime/lua/ime_translate/state.lua`,
`tests/test_backend.lua`, `tests/test_state.lua` (uncommitted)
Time: 2026-09-23 15:50 UTC

Round 1's yellow (glued URL → deterministic `bad_guard`) and green (q checked by
substring) are both addressed: `guard` spaces the placeholder off after an
ASCII `%w` byte (`backend.lua:68`), and the test now decodes the `-d` body and
compares `q`.

### 🔴 Must fix
- `rime/lua/ime_translate/backend.lua:83` with `:60` — the new `(%w?)X_n`
  pattern in `unguard` accepts a placeholder glued to a letter. But `guard`'s
  pre-check still requires a `%f[%w]` frontier, so a draft holding an
  identifier that ends in `X_<digit>` (`MAX_1`, `BOX_2`, `INDEX_1`) is still
  guarded. The two now disagree about what counts as a placeholder.
  Reproduced:
  `guard("设置 MAX_1 见 https://a.com")` → `设置 MAX_1 见 X_1`. If `translate`
  drops the placeholder and returns `Set MAX_1 see`, `unguard` counts 1 (the
  `AX_1` inside `MAX_1`) and returns `Set MA https://a.com see`. That is
  `ok = true`: the identifier is mangled and the URL lands in the wrong place,
  and all of it is committed. §7.5 promises that a placeholder which does not
  come back fails as `bad_guard`, and acceptance item 3 says the same. Round 1
  met both for this input, because its leading frontier did not match `AX_1`
  and so counted 0. So round 2 breaks an acceptance item that previously
  passed. The same input also fails deterministically when the placeholder
  *is* kept: `Set MAX_1 see X_1` counts 2 and gives `bad_guard`, and
  `MAX_2 和 <url> 和 <url>` fails the same way.
  Fix: make the pre-check refuse any `X_<digit>` in the draft, with no
  frontier (`text:find("X_%d")`). Then no literal token can collide with the
  glued-placeholder match. Add a row asserting that
  `设置 MAX_1 见 https://a.com` is sent unguarded.

### 🟡 Should fix
- None.

### 🟢 Suggestions
- None.

### What was walked
- Dimension 1: unchanged since round 1. `bad_guard` is an ordinary
  `(false, code)` and the processor's `set_error` keeps the draft. The 🔴
  above is not text loss: it commits a *wrong* translation, not an empty one.
- Dimensions 2–5: still untouched by this diff (pure string functions; the
  URL list is a local; the body goes through `json.shq`).
- Dimension 6: mutation in a scratch copy (repo untouched), on the new code.
  These mutants all went red: dropping the separator; spacing only after
  letters, not digits; dropping the re-inserted space; putting the leading
  frontier back; dropping the trailing frontier; allowing a doubled
  placeholder. `(%w?)` → `(%w*)` survived, but it is equivalent (the extra
  captured letters are re-emitted unchanged), so it is not a gap. No test
  covers a literal `…X_n` token in the draft, which is why the 🔴 is green in
  the suite.
- Glued-placeholder edge cases probed: `X_2X_1` restores both URLs, each
  spaced; `X_1X_2` fails (`X_1` is followed by `X`, so the trailing frontier
  refuses it), which is a safe failure; `X_1a` and `X_12` are refused. After
  Chinese, no space is added (`看X_1`).
- The decoded-body row: `body_q:match("%-d '(.*)'$")` relies on `json.shq`
  single-quoting and on no `'` in the body. That holds for this fixed input,
  and a mismatch would error rather than pass.
- Dimension 9: the space inserted after a glued word changes the committed
  English (`seehttps://…` → `see https://…`). This is deliberate, stated in
  the comment, and reads better. It is not a deviation from §7.5, which
  guarantees the URL, not the surrounding whitespace.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | all files PASS, exit 0 (test_backend 167, test_state 18) |
| The libretranslate request carries X_n in place of each URL, and the result carries the URLs as typed | ok | decoded `q` equals `看一下 X_1 这个仓库`; result row passes |
| A placeholder missing or doubled fails with bad_guard; the draft stays | **broken for drafts holding `…X_<digit>`** | see 🔴: `Set MAX_1 see` returns ok with `Set MA https://a.com see` |
| The openai and anthropic requests are unchanged | ok | rows unchanged; no `prepare` on those adapters |

### Verdict
1 red / 0 yellow / 0 green. The task **cannot** be marked done.

## Task 3: The cache and the route, with the cloud-to-local fallback — round 2

Range: uncommitted work on `5c2b84f` — the same Task 3 files as round 1
(`cache.lua`, `route.lua`, `tests/test_cache.lua`, `tests/test_route.lua`,
`git diff HEAD -- rime/lua/ime_translate_shared.lua tests/test_shared.lua
tests/test_glue_load.lua`). Task 4's and Task 5's uncommitted changes in the
tree are out of scope.
Time: 2026-09-23T15:51Z

### 🔴 Must fix
None.

### 🟡 Should fix
None. Round 1's yellow is closed: `tests/test_route.lua:91-98` configures an
`openai` local slot at `127.0.0.1`, times the cloud out, and asserts that the
fallback request carries `LOCAL-KEY` and not `CLOUD-KEY`. Mutating
`route.lua:40` to `S.cloud_key` in a scratch copy now turns `test_route` red
(checked independently, not only as reported).

### 🟢 Suggestions
- `rime/lua/ime_translate_shared.lua:4` — round 1's green 3 is reported fixed
  but is not: the rewrap moved the overflow, and line 4 is now 110
  characters, still past the width of the rest of the header.
- `tests/test_route.lua:79-80` — the comment introducing the local-key case
  sits above the `FALLBACK_MS` / settings-unchanged assertions (lines 81-82),
  eleven lines before the case it describes (line 91). Move it down to the
  case.
- Round 1's green 2 (the redundant `too_long` guard) is kept on purpose, as
  a statement of the rule where the fallback is decided; accepted, no
  further note.

### Paths walked and what was verified
- `route.lua` and `cache.lua` are unchanged since round 1, so round 1's walk
  of dimensions 1, 2, 4, 5, 7, 8 and 9 stands. `shared.lua` changed only in
  its header comment.
- The new test case: `CFG_OA` loads a local slot of `openai` at loopback,
  plus the `CFG` cloud slot; `S.current()` in `fake_shared` reads
  `S.settings.cloud` dynamically, so replacing `S.settings` keeps the cloud
  slot live; the fake runner's `127.0.0.1` routing classifies the fallback
  as local. The case asserts `fallback = true` and both key conditions.
- `tests/test_cache.lua:18-21`: `("ab","c")` against `("a","bc")`. Without
  the length prefix both keys are `"abc"`, and the mutant now goes red.
- Mutants rerun in a scratch copy: fallback key, caching errors, fallback
  timeout 2500, the local code on a double failure, the fallback's `cloud`
  flag, no cache read, `get` not refreshing, no length prefix, off-by-one
  capacity, `ensure` rebuilding — all red. Only the `too_long` guard stays
  green, as expected and accepted.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | 13/13 PASS; test_route 46, test_cache 17, test_shared 36 |
| A failed cloud request is followed by one local request with a 500 ms timeout; its success is marked fallback | ok | rows 70-78, 91-98; mutants red |
| A local failure is never sent to the cloud; too_long never falls back | ok | rows 52-57, 115-118 |
| A cached slot and draft make no request; errors are never cached | ok | rows 42-50, 58-60; mutants red |

### Verdict
0 red / 0 yellow / 2 green — no red, clear to close.

---

## Task 2: The URL guard in the libretranslate adapter — round 3

Range: `HEAD` (5c2b84f) working tree, limited to
`rime/lua/ime_translate/backend.lua`, `rime/lua/ime_translate/state.lua`,
`tests/test_backend.lua`, `tests/test_state.lua` (uncommitted; the other
modified files belong to later tasks and were not reviewed)
Time: 2026-09-23 15:52 UTC

Round 2's red is fixed as proposed. `guard`'s pre-check is now
`text:find("X_%d")` (`backend.lua:60`), with no frontier. The comment says why:
`unguard` also takes a placeholder glued to a word.
`tests/test_backend.lua:263-264` asserts that `设置 MAX_1 见 https://a.com` goes
unguarded, with no list.

### 🔴 Must fix
- None.

### 🟡 Should fix
- None.

### 🟢 Suggestions
- None.

### What was walked
- The round 2 repro, re-run against the working tree:
  `guard("设置 MAX_1 见 https://a.com")` now returns the draft unchanged and
  `nil`. `finish` passes that through untouched, so
  `Set MAX_1 see <url>`-style output can no longer be rewritten. The
  pre-check and `unguard` now agree: any `X_<digit>` in the draft, glued or
  not, keeps the whole draft unguarded. So the `(%w?)X_n` match can only ever
  see placeholders that `guard` itself inserted.
- Dimension 6: in a scratch copy (repo untouched), putting the old
  `%f[%w]X_%d` pre-check back turns `test_backend` red, so the new row can
  fail. Round 2's mutants for the separator, the re-inserted space, both
  frontiers and the doubled-placeholder check were not affected by this
  change.
- The rest of the `backend.lua` diff was checked for anything beyond the
  guard. It contains only the guard, `prepare`/`finish`, `sent` in the body,
  and the `bad_guard` return; no Task 3 changes are mixed in.
- Dimensions 1–5: unchanged from rounds 1–2. A failure keeps the draft
  through `set_error`. No commit/candidate/invalidation/Context change. The
  body is still `json.shq`-quoted.
- Cost of the stricter pre-check: a draft that holds a literal `X_<digit>` is
  sent unguarded, so its URL is exposed to the gluing §7.5 describes. This is
  the behaviour §7.5 already specifies ("a draft that already holds such a
  token is sent unguarded"), and it is safe.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | 13/13 PASS, no FAIL; test_backend 169 assertions |
| The libretranslate request carries X_n in place of each URL, and the result carries the URLs as typed | ok | decoded `q` row and result row pass |
| A placeholder missing or doubled fails with bad_guard; the draft stays | ok | the round 2 counter-example is now unguarded; missing/doubled rows and the translate-level `bad_guard` row pass |
| The openai and anthropic requests are unchanged | ok | rows unchanged; no `prepare` on those adapters |

### Verdict
0 red / 0 yellow / 0 green. No red, clear to close.
