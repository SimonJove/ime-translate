# Review log

Every task is reviewed by `task-reviewer` before it is marked done; the
procedure is `.claude/skills/task-review/SKILL.md`. Any 🔴 means another round,
and **each round is appended, never overwritten** — what was found and how it
was fixed is the only record this project will have of why the code looks the
way it does.

Documentation-only tasks are not reviewed.

---

## Task 2: Scaffolding + JSON string encoding — round 1

Range: `ddb5d16..HEAD` is empty: the change is staged, not committed. Reviewed
as `git diff ddb5d16` (staged content equals the working tree for all three
files). `progress.json` changes are ledger state from `progress.sh`, not
reviewed as task code.
Time: 2026-09-21T05:08Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- `rime/lua/ime_translate/json.lua:8`: the `%c` class in `json.escape` is
  locale-dependent, so whether Chinese text passes through intact depends on
  process-global C state that this module does not own. Lua's `%c` is
  `iscntrl()`. On macOS, with a UTF-8 `LC_CTYPE`, `iscntrl()` is true for 33
  bytes of 0x80 and above (0x80-0x9F and 0xAD), and those are ordinary UTF-8
  continuation bytes. Headless run, Lua 5.4.8, this Mac: after
  `os.setlocale("en_US.UTF-8", "ctype")` (also `zh_CN.UTF-8` and `C.UTF-8`),
  `json.escape` of U+4E2D U+6587 rewrites the bytes 0xAD, 0x96 and 0x87 as
  `­`, `\u0096` and `\u0087`, which leaves invalid UTF-8 beside them.
  About half of all CJK characters contain one of these bytes, so almost every
  sentence is hit. The server rejects the body (400, which becomes an error
  candidate) or translates garbage, and the user gets no usable translation.
  Trigger: any Lua component that shares librime-lua's single Lua state
  (design §6.1) calls `os.setlocale` with a UTF-8 locale. That could be the
  user's other Rime Lua plugins or a later task of ours. The locale is
  process-wide. Current state, a derivation and not measured in the IME:
  `nm -u` shows that neither `Squirrel` nor `librime.1.dylib` imports
  `setlocale`. The import in `librime-lua.dylib` is Lua's own `os.setlocale`.
  The running Squirrel process has no `LANG`/`LC_*` in its environment, and
  `~/Library/Rime` holds no Lua yet. So the code works today and the trigger
  is absent. The unit test cannot see the problem: the standalone `lua` never
  calls `setlocale`, so assertion #6 only ever runs under `C` (the
  fake-environment trap of dimension 8). Fix: use an explicit byte class, e.g.
  `'[\0-\31\127"\\]'`. Verified: under `C` it matches the same 35 bytes below
  0x80 that `[%c"\\]` does, and under `en_US.UTF-8` it matches 0 bytes of 0x80
  and above. The assertion count stays 10. The plan's own code has the same
  line; this is not an implementation deviation.

### 🟢 Suggestions
- `rime/lua/ime_translate/json.lua:4-5,8-9`: no assertion anywhere reaches
  the control-character path, meaning the `\u%04X` fallback and the `\r`, `\b`
  and `\f` table entries. Mutation run against a scratch copy (repo not
  touched): all 10 assertions still pass when (a) the class is reduced to
  `["\\\n\t]` (so `\r`, NUL and U+0001 go into the JSON raw), (b) the fallback
  emits `\x01`, (c) the fallback returns `""` (control characters silently
  dropped), or (d) the `\b`/`\f` entries are deleted. The current code is
  correct: `escape("a\rb\0c\1d\127e\b\f")` gives
  `"a\rb\u0000c\u0001d\u007Fe\b\f"`. Later plans do not cover this path
  either: Task 3 has no escape round trip, and Task 6 asserts only `\n`.
  Scenario: Task 3 edits this same file, a fallback regression survives both
  suites, and the first input with such a character produces a body that JSON
  rejects. Real sources of such characters are rare, because YAML normalizes
  line breaks and Rime composition does not emit control characters, so this
  is green. Adding an assertion here would make acceptance item 1 ("prints 10
  assertions OK") literally false, so it needs the user's consent to the new
  count. The alternative is a `decode(escape(s)) == s` round trip over bytes
  0-31 and 127 in Task 3's test.

### Deviations from the plan
- `tests/test_json_encode.lua:9-11,18`: the plan's CJK literal is spelled as
  UTF-8 byte escapes because `checks_language` refuses CJK in `tests/*.lua`.
  It is explained in the file and equivalent: `utf8.codepoint` on the bytes
  gives U+4E2D U+6587, and the runtime string is identical to the plan's. The
  assertion can fail: a mutation that also escapes bytes 0x80-0xFF turns #6
  red. Neither an improvement nor an omission, so accepted. Note outside this
  task: plans 03 (lines 37, 39) and 06 (line 54) put CJK in `tests/*.lua`
  too, and `rules/core.md` lists "Chinese test sentences" as a language
  exception that `checks.sh` does not grant for `tests/`.
- `.gitignore` unchanged: `eval/results-*.md` was already present at
  `ddb5d16`, so the plan's `grep -q` guard correctly skipped the append.
- `json.lua` and `run_tests.sh` are otherwise byte-identical to the plan.

### What was walked
- Dimensions 1-4 and 7 do not apply: the diff has no `ctx:clear`, no
  `commit_text`, no processor, translator or session code, and no design
  constants. The only module-level value is the read-only `escapes` table.
- Dimension 5 (json.shq): verified by inspection, by mutation, and by 17
  hostile strings, below.
- Dimension 6: mutations to `shq` (`%q`, no quote rewriting) and to the `"`
  escape are killed by assertions #7, #8 and #2. The escape control-character
  gap is the green item above.
- Dimension 8: `json.lua` makes no claim about engine behaviour. Its implicit
  host-locale assumption is the yellow item.
- `.githooks/pre-commit` run over the staged content (read-only): exit 0.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_json_encode.lua` prints 10 assertions OK | ok | Re-run: `test_json_encode: 10 assertions OK`, exit 0. `scripts/run_tests.sh` exit 0 |
| `json.shq` uses POSIX single quotes, not `string.format('%q', ...)` | ok | `json.lua:19` wraps the string in `'...'` and rewrites `'` as `'\''`. `%q` appears only in the comment at line 16. Mutating to `string.format("%q", s)` turns #7 red. 17 hostile strings went through `io.popen("printf %s " .. shq(s))` (/bin/sh) and came back byte-exact: empty, single and repeated quotes, `$(touch /tmp/PWNED_shq)`, backticks, `${HOME}`, newline, backslashes, `!`, leading `-`, `%`, tab, DEL, CJK bytes. No injection artifact was created |

### Verdict
0 red / 1 yellow: no red, clear to close. Fix the yellow or defer it with a
one-line reason.

---

### Author's response (round 1)

- **Yellow — fixed.** Reproduced first: after `os.setlocale("en_US.UTF-8",
  "ctype")`, `json.escape` turned U+4E2D U+6587 into
  `"<E4><B8>­<E6>\u0096\u0087"`. `json.lua` now uses the explicit class
  `[\0-\31\127"\\]`; under `C` it matches the same 35 bytes `%c` did, and under
  UTF-8 it matches no byte at 0x80 or above. The test now switches to a UTF-8
  ctype before its assertions (stderr note if the machine has none), so
  assertion #6 runs under the condition that broke — against the old line it
  failed with exactly the corruption above; against the fix it passes. Count
  unchanged: `test_json_encode: 10 assertions OK`.
- **Green — deferred.** Covering the control-character path here changes the
  acceptance count, which is the user's to change. Suggested instead: a
  `decode(escape(s)) == s` round trip over bytes 0-31 and 127 in Task 3's test,
  added to Task 3's plan before it starts if the user agrees.
- **The CJK-in-tests conflict** noted under deviations is raised to the user; it
  recurs in plans 03-07.

---

## Task 3: JSON decoding — round 1

Range: `1fabfc8..HEAD` is empty because the change is staged, not committed. It
was reviewed as `git diff 1fabfc8`. For `json.lua` and
`tests/test_json_decode.lua` the staged content equals the working tree. The
only unstaged change is `progress.json`. That is ledger state from
`progress.sh` (`in_progress`, `startedAt`, `baseCommit` = 1fabfc8), it is
consistent, and it is not reviewed as task code.
Time: 2026-09-21T05:54Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- None.

### 🟢 Suggestions
- `tests/test_json_decode.lua:31-38`: the "real response shapes" are
  trimmed. They contain no `null`, no `[]` and no `{}`, and no other assertion
  in the file decodes an empty container. Mutation run against a scratch copy,
  with the repo untouched: deleting the empty-array early return
  (`json.lua:124`) or the empty-object early return (`json.lua:106`) keeps all
  79 assertions green. The array mutant then returns `nil, "bad number at 43"`
  for `{"message":{"content":"Hi","annotations":[]}}`. Current OpenAI chat
  completions put `"refusal": null, "annotations": []` inside `message`.
  Anthropic messages carry `"stop_sequence": null` and nested `usage` objects.
  (That comes from the vendors' API references: a derivation, not a captured
  response.) So a regression of this kind would pass the suite and turn every
  OpenAI translation into `bad_json`. The current code is correct: full-field
  bodies from both vendors decode and yield the translation (see acceptance
  below). Suggestion: add one full-field body per vendor. That would also make
  "real" in acceptance item 3 literally true of the test.
- Same file, other decode paths that are correct today but that no assertion
  reaches. Each mutant survives all 79 assertions:
  - Negative exponents: changing `json.lua:92` from `[+-]?` to `%+?` makes
    `{"x":1e-05}` fail, and Python's `json` writes small floats that way.
  - The `\/` entry at `json.lua:59`: without it, `"https:\/\/x.test"` fails
    with `bad escape`, and PHP-style encoders emit that escape.
  - `\r` in the whitespace class at `json.lua:46`: without it, every
    CRLF-formatted body fails.
  - The low-surrogate range check at `json.lua:71`: without it,
    `"\ud800A"` silently decodes to U+2441 instead of being refused.

  One assertion each would pin them.
- `json.lua:113,126`: the `and e` / `and e2` conjunct in `if v == nil and e`
  is now dead. Every failure return carries a message (listed under "What was
  walked"), and replacing the line with `if v == nil` is an equivalent mutant
  (79 OK). But the conjunct fails open. It is the line that turned the plan's
  message-less `tonumber` nil into a silent drop (`[1e]` and `{"a":1e}` both
  decode to `{}`; reproduced against the plan's code). If a later edit brings
  back a bare-nil return, the element disappears again instead of the document
  being refused. `if v == nil then return nil, e or err("no value") end` would
  fail closed.

### Deviations from the plan
- Test: lines 1-47 are byte-identical to the plan's block, including the round
  trip logged in `decisions.md` on 2026-09-20. Lines 48-62 add 20 regression
  assertions. The deviation is explained, and acceptance 1 names no count, so
  this is an improvement. Reproduced against the plan's decoder, rebuilt in
  scratch as Task 2's `json.lua` at 1fabfc8 plus plan lines 79-183: the plan's
  block passes 59, and the full file first fails at
  `#61 malformed number carries a message: 1e`. Against Task 2's `json.lua`,
  which has no decode, the file fails at line 9, so step 2's red state holds.
- `json.lua:82-97`, the `parse_number` rewrite: an improvement.
  - The plan's defects are reproduced: `1e` and `1e+` give (nil, nil),
    `[1e]` and `{"a":1e}` give an empty table, and `1.` and `[1.]` are
    accepted as 1.0.
  - Exhaustive sweep: every string of length 1-6 over `- + . e E 0 1 9`
    (299,592 strings), each decoded at top level, inside an array and as an
    object value. Zero valid numbers are rejected. Zero invalid ones are
    accepted, except those with leading zeros (1,932 strings). There are zero
    raises and zero nils without a message, and every accepted value equals
    `tonumber` of the literal.
  - Leading zeros (`01` → 1, `-007.5` → -7.5) are read as decimal, not
    octal, so nothing is misread. RFC 8259 §9 lets a parser accept
    extensions, and no mainstream serializer emits leading zeros. The three
    adapters read only strings. This does not matter.
- `json.lua:28-30,98-99`, the depth limit: an improvement, and acceptance 2
  requires it (reproduced: the plan's decoder raises `stack overflow` on 10^6
  nested arrays).
  - Every recursion goes through `parse(depth + 1)` (lines 113 and 126).
    `parse_string` and `parse_number` are iterative. The check sits at
    `parse`'s entry, so it bounds both container kinds and scalars.
  - Measured: 201 value levels decode and 202 are refused with `too deep`,
    for arrays, objects and alternating nesting. 10^6 unclosed `[` and 10^6
    unclosed `{"a":` are both refused without raising. 200 levels still
    decode under a coroutine + pcall + 150 existing Lua frames.
  - `MAX_DEPTH` is a read-only module constant. It would not differ per input
    box, so dimension 4 is satisfied.

### What was walked
- Dimensions 1-3 and 5 do not apply. The diff has no `ctx:clear`, no
  `commit_text`, no processor, translator or session code, and no shell
  construction.
- Dimension 4: the module-level values are `M.null` (an identity sentinel that
  planned consumers only read), `MAX_DEPTH` (a constant) and `utf8_enc` (a pure
  function). `pos` and the closures are locals of each call, and decode is
  re-entrant: after a refusal, the next decode parses normally.
- Error propagation, with every return in decode enumerated:
  - `parse_string` fails at lines 49, 54, 63, 67, 69, 71, 74 and 76.
  - `parse_number` fails at lines 89 and 94.
  - `parse` fails at lines 99, 101, 111, 119 and 132.
  - All of these return `nil, err(...)`.
  - Lines 109, 113 and 126 pass on a message that is already non-nil
    (by induction).
  - Success returns are never nil: table, array, string, true, false,
    `M.null` or a number. So `parse` never returns a bare nil.
  - Fuzzing agrees. Under pcall, 180,000 random mutations of three response
    bodies and 100,000 random byte strings of 0-12 bytes gave 0 raises and 0
    nils without a message.
- Malformed battery of 72 inputs: truncations, bad escapes, lone and
  mismatched surrogates, trailing commas, `NaN`, `Infinity`, a BOM, unbalanced
  brackets, concatenated documents and bad numbers. There were 0 raises, 0
  accepted inputs and 0 refusals without a message.
- Differential test against Python's `json`, over 3,000 random documents:
  - Strings contain control bytes, `"`, `\`, `/`, U+2028, and BMP, astral and
    U+10FFFF characters.
  - Integers go up to 2^62. Floats include 1e-05, 1.5e-300 and -0.0.
  - Nesting goes to depth 7. Half use `ensure_ascii=True`, so astral
    characters arrive as surrogate pairs. One fifth are pretty-printed.
  - Each was decoded in Lua, re-encoded and compared in Python: 0 failures
    and 0 mismatches.
- Locale, following Task 2's lesson:
  - Under C, en_US.UTF-8, zh_CN.UTF-8 and de_DE.UTF-8 ctypes, `%d` and `%x`
    match no byte at 0x80 or above, and the whitespace class is explicit.
  - The full test passes with each of those set as the process locale.
  - Under a comma-decimal LC_NUMERIC, `tonumber` still reads `1.5`, because
    Lua retries with the locale's decimal point. Only a float literal longer
    than 200 characters fails. It then fails as `bad number` through the guard
    at line 94, not as a raise, and no backend emits such a number.
- Dimension 6: 23 mutations were run.
  - Killed: depth check removed, `MAX_DEPTH` set to 10 or 1e9, fraction
    digits made optional, `\b` mapped wrong, `null` returning nil, the
    trailing-garbage check removed, negative integers dropped, the fraction
    dropped, and uppercase hex rejected.
  - Survivors are equivalent mutants, the unreachable guard at line 94, or the
    coverage gaps listed under Suggestions. The equivalent mutants are
    optional exponent digits (masked by the `tonumber` guard, so the input is
    still refused with a message) and removing `and e`.
- Dimension 7: the diff has no design constants.
  - §7.6 says to walk `content[]` for `type == "text"`. That depends on
    elements keeping their order and on a null not cutting the array short.
    Elements are appended in order, and a JSON null inside `content[]`
    becomes the `M.null` table, so `ipairs` does not stop there.
  - §8.1: malformed input gives (nil, message), which Task 6's plan maps to
    `bad_json` without needing a pcall.
  - §7.3: the message carries only a reason and a byte offset, never response
    content, so nothing from the body reaches a log through it.
- Dimension 8: the bitwise operators in `utf8_enc` need Lua 5.3 or later.
  `docs/spike-report.md` records Lua 5.4.6 inside librime-lua, taken from the
  dylib's version string. That 200 levels are also safe on 5.4.6 is a
  derivation, not measured in the IME. It rests on 5.4's Lua-to-Lua calls
  taking no C frame, and on 5.4.8 running 350 nested Lua frames here without
  error.
- `.githooks/pre-commit` run over the staged content (read-only): exit 0.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_json_decode.lua` passes every assertion | ok | Re-run: `test_json_decode: 79 assertions OK`, exit 0. `scripts/run_tests.sh` exits 0 (encode still 10 OK). The test also passes with en_US, zh_CN and de_DE UTF-8 set as the process locale |
| Malformed input returns nil plus an error message string; never raises | ok | 72-input battery, 280,000 fuzz inputs and 898,776 number-grammar documents: 0 raises, 0 nils without a message. 10^6-deep nesting is refused with `too deep` |
| Both real OpenAI and Anthropic response shapes yield the translation | ok | Test #21-#24 cover trimmed shapes. Full-field vendor bodies also yield the translation: OpenAI with `refusal: null`, `annotations: []` and nested `usage`; Anthropic with a signed thinking block first, `stop_sequence: null` and `usage.cache_creation`. Those two bodies are a derivation from the API references. The LibreTranslate body measured in `spike-report.md` line 92 also decodes. No live backend answered (127.0.0.1:8989 was down), so none of this is a captured response |

### Verdict
0 red / 0 yellow: no red, clear to close. The three greens are advisory.

---

### Author's response (Task 3, round 1)

All three greens taken; no red or yellow was open.

- **Green 1 — done.** Full OpenAI and Anthropic bodies, written from the API docs
  with `refusal: null`, `annotations: []`, `logprobs: null`, empty `{}` details
  and `stop_sequence: null`, plus bare `{}` and `[]`. Dropping the empty-array or
  the empty-object branch now fails the suite.
- **Green 2 — done.** Assertions for a negative exponent, `\/`, a CRLF-wrapped
  body, and a high surrogate followed by a non-low escape.
- **Green 3 — done.** Both container checks now read
  `if v == nil then return nil, e or err("no value") end`: a value-less nil
  refuses the document instead of dropping the member.
- **Mutation check of the additions**, on a scratch copy: dropping the empty-array
  branch, the empty-object branch, negative exponents, the `\/` escape, `\r` as
  whitespace, the low-surrogate range check, and the depth check — 7 of 7 killed.
  The low-surrogate mutant decoded `"\ud800A"` to U+2441, as the review
  predicted.
- `test_json_decode: 88 assertions OK`; `scripts/run_tests.sh` exit 0.

---

## Task 4: Phase constants and error strings — round 1

Range: `7f289c4..HEAD` is empty because the change is staged, not committed. It
was reviewed as `git diff 7f289c4`. For `state.lua` and `tests/test_state.lua`
the staged content equals the working tree. The only unstaged change is
`progress.json`. That is ledger state from `progress.sh` (Task 3 `done` with
commit 7f289c4, Task 4 `in_progress` with `baseCommit` = 7f289c4). It matches
`git log` and is not reviewed as task code.
Time: 2026-09-21T06:11Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- None.

### 🟢 Suggestions
- `tests/test_state.lua:25-27`: the comment says "The module must export no
  mutable state", but the two assertions only check that `state.new` and
  `state.phase` are nil. A module-singleton FSM under any other name gets
  through. Mutation runs against a scratch copy, with the repo untouched. Each
  of these passes all 16 assertions:
  - `M.current = M.IDLE`, plus `set_phase` and `get_phase` functions
  - `M.sessions = {}`
  - `M.messages = messages`, which lets any consumer mutate the strings

  Scenario: a later task takes a shortcut and keeps the phase in `state.lua`
  behind a setter. That is the regression acceptance 2 exists to stop, and
  `test_state` stays green. Task 7's "ctx b unaffected by ctx a" assertion
  catches it only if `session.lua` itself goes through that setter.
  Suggestion: pin the export set once, at the end of the file, after the
  `error_message` calls:

  ```lua
  local allowed = { IDLE = "string", RESULT = "string", ERROR = "string",
                    BUSY = "string", error_message = "function" }
  local stray
  for k, v in pairs(state) do if allowed[k] ~= type(v) then stray = k end end
  eq(stray, nil, "exports only the four phase constants and error_message")
  ```

  Checked in scratch: the unmodified module passes with 17 assertions, and all
  three mutants fail at #17. Acceptance 1 names no count, so the addition is
  allowed. It departs from plan step 4's "16 assertions OK", so it needs one
  sentence of explanation.

### Deviations from the plan
- None. `git show :path` of both files is byte-identical to the plan's two code
  blocks (task-04-state.md lines 33-60 and 73-98).

### What was walked
- Dimensions 1-3 and 5 do not apply. The diff has no `ctx:clear`, no
  `commit_text`, no processor, translator or session code, and no shell
  construction. D1 is still open and blocks Tasks 7 and 9. This diff touches
  none of the files D1 governs, so D1 raises no red here.
- Dimension 4 (session state):
  - The module-level values are `M` (four string constants and one pure
    function) and the local `messages` table. `messages` is never written
    after it is built and is not exported, so no consumer can reach it.
    `error_message` reads only its argument and `messages`.
  - No value here would differ because the user moved to another input box.
  - `pairs(state)` gives exactly BUSY, ERROR, IDLE and RESULT (strings) plus
    `error_message` (function). The module has no metatable.
  - The phase itself lives in Context: Task 7's plan writes only
    `state.IDLE`, `state.RESULT` and `state.ERROR` into `ime_translate.phase`.
- Dimension 6 (can the test fail?): 20 mutants were run.
  - Killed:
    - the fallback changed to another message, changed to `""`, or removed
    - `auth_error` and `rate_limited` swapped
    - `conn_refused` and `timeout` swapped
    - the space after the mark removed
    - U+2718 used instead of U+2717
    - an `assert(code)` guard added (killed by the nil case)
    - `BUSY` removed
    - `IDLE = ""`
    - `RESULT` equal to `ERROR`
    - `state.new` put back, and `state.phase` put back
  - Survivors:
    - Deleting the `http_error`, `bad_json` or `empty` entry. These are
      equivalent mutants: those three entries have the same string as the
      fallback, so every input still gives the same output.
    - The three export mutants in the green above.
  - Step 2's red state holds. With no `state.lua`, the test stops at line 2
    with `module 'ime_translate.state' not found`.
- Dimension 7 (constants):
  - Checked independently of the author's check. The §8.1 table from
    `design-section.sh 8.1` has 8 codes, and `error_message(code)` is
    byte-equal to each backticked message, with 0 differences.
  - Every message is `E2 9C 97` (U+2717), then `20` (ASCII space), then CJK.
    There is no NBSP and no full-width space.
  - The test's eight literals also equal the design's. So the test and the
    implementation do not share a divergence from §8.1.
- The fallback carries weight:
  - Task 9's filter plan builds `msg .. " " .. (cand.comment or "")`, which
    raises if `msg` is nil. The no-fallback mutant is killed by #13 and #14.
  - Task 7's `session.code` returns `""` when the property is unset, and
    `error_message("")` gives the fallback.
  - None of these arguments raises, and each gets the fallback: `"__index"`,
    `""`, `1`, `true`, `0/0`, `{}`, `"TIMEOUT"`, `" timeout"`, or no argument
    at all.
- Codes produced against codes consumed:
  - Task 6's plan produces exactly the eight codes (task-06-backend.md lines
    227-261; an unknown adapter maps to `http_error`). Task 7's test uses
    `timeout`. No planned producer emits a code this table lacks.
  - The module exports no list of codes, so this contract is two independent
    sets of string literals. A typo on the producer side would show the
    generic failure string instead of the specific one. Task 6's review, under
    dimension 7, is where that gets checked.
- Consumers: Tasks 7 and 8 use `IDLE`, `RESULT` and `ERROR`. Task 9's
  translator uses `RESULT`, and its filter uses `ERROR` and `error_message`. No
  other part of `state` is referenced in plans 05-12. Nothing a consumer needs
  is missing.
- `BUSY` against design §5.4: consistent.
  - §5.4 keeps the value, marks it unreachable, and says the intercept test
    does not check it. §6.1's property table lists only idle, result and
    error.
  - No planned code writes or reads `state.BUSY`. A grep over `plan/`, `rime/`
    and `tests/` finds only the definition and assertion #4.
  - §5.4 names `should_intercept_return()`, which no plan defines. Its
    successor `decide.decide` (Task 8) has no busy branch. A busy phase would
    fall into `phase ~= IDLE` → `invalidate_and_pass`, which is harmless
    because the phase is unreachable.
- Dimension 8 (upstream assumptions):
  - `state.lua:5-7` asserts engine behaviour ("librime is single-threaded and
    receives no keys at all"). No F-row in §15.2 and no spike-report verdict
    backs it; its only source is §5.4.
  - It is not raised as a finding. Its conclusion does not depend on that
    premise: `busy` cannot be observed because no code ever writes it. No red
    line rests on the premise either.
  - The premise itself is a derivation: the Lua processor blocks inside
    Squirrel's synchronous `process_key`, so no second key enters the engine
    during the call.
  - What happens to keys typed during the freeze is the "typing during the
    wait" row of the compatibility matrix, for Tasks 10 and 11 to measure.
- Language: `state.lua` is on `checks_language`'s whole-file list (checks.sh
  line 215), and its comments are English. `.githooks/pre-commit` run over the
  staged content (read-only) exits 0, with all 3 test files passing.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_state.lua` passes every assertion | ok | Re-run: `test_state: 16 assertions OK`, exit 0. `scripts/run_tests.sh` exits 0 (decode 88, encode 10, state 16) |
| `state.new` does not exist | ok | Assertions #15 and #16. Mutants that put back `M.new` or `M.phase` are killed there. The export set is only the four constants and `error_message`. The green above covers regressions under other names |
| The eight error strings match §8.1 word for word | ok | Byte comparison against the parsed §8.1 table: 8 codes, 0 differences. The test's literals match too |

### Verdict
0 red / 0 yellow: no red, clear to close. The one green is advisory.

---

### Author's response (Task 4, round 1)

- **Green — done.** One assertion (#17) pins the export set to exactly `BUSY`,
  `ERROR`, `IDLE`, `RESULT` (strings) and `error_message` (function), failing with
  the names of any stray keys. The three variants the review found passing —
  `M.current` with `set_phase`/`get_phase`, `M.sessions = {}`, and an exported
  `M.messages` — each fail at #17 on a scratch copy; the real module passes.
- Deviation from the plan: `test_state: 17 assertions OK` where plan Step 4 says
  16. Acceptance item 1 names no count. `state.lua` itself is unchanged and still
  byte-identical to the plan.

---

## Task 5: Config loading and validation — round 1

Range: `f84acb2..HEAD` is empty because the change is staged, not committed. It
was reviewed as `git diff f84acb2`. For `config.lua`, `tests/test_config.lua`
and the plan's one-line fix, the staged content equals the working tree. The
only unstaged change is `progress.json`: ledger state (Task 4 `done` with
f84acb2, Task 5 `in_progress` with `baseCommit` = f84acb2), consistent with
`git log`, not reviewed as task code.
Time: 2026-09-21T07:12Z

### 🔴 Must fix
- `rime/lua/ime_translate/config.lua:37-42`: `is_loopback` still disagrees
  with curl, and Task 6's plan hands `base_url` to curl verbatim
  (`json.shq(ad.endpoint(settings))`, task-06 line 241, no `--globoff`). The
  curl command-line tool expands `{a,b}` and `[1-9]` globs in a URL before it
  parses it. A glob placed after the port can hide an `@` behind a `/`, `?` or
  `#`. `is_loopback` then sees the authority `localhost:8989{` (host
  `localhost`, no `@`), while curl sends a second request to another host:

  `base_url: http://localhost:8989{/,@evil.example/}`

  expands to `http://localhost:8989//translate` and
  `http://localhost:8989@evil.example//translate`. Measured on this Mac, curl
  8.7.1: `config.load` keeps that URL with `allow_remote` false and 0 warnings.
  The command shape Task 6's plan builds, plus `--resolve` mapping
  `evil.invalid` to 127.0.0.1 so nothing left the machine, run through
  `/bin/sh`, delivered the request body to a local listener twice: once as
  `Host: localhost:18990` and once as `Host: evil.invalid:18990`. Without
  `--resolve`, curl resolves that host through DNS. `{#,@evil.example}` and
  `{?,@evil.example/}` do the same. With `allow_remote: true` the URL still
  counts as loopback, so the remote copy goes over plain http. Consequence:
  every sentence the user confirms goes to a third party, over http, with no
  `allow_remote` line in the file and a URL that reads as localhost.
  Acceptance items 4 and 5 do not hold for this input. From the plan's runner
  (a derivation), the concatenated output decodes as `bad_json`, so the user
  sees only an error candidate, and only after the text has left.

  Threat model, for the user's call: this needs someone to write the config
  file. Design §7.3 notes that `~/Library/Rime` is commonly synced through
  GitHub. Such a person could also write `allow_remote: true` plus an https
  URL. But that is the visible, deliberate switch §7.2 exists for, and it
  forces https. This is the same class as the userinfo forms this task already
  fixed as acceptance failures. The plan's prefix match had it too, so it is
  residual, not introduced.

  Fix, checked on a standalone copy with the repo untouched: accept a loopback
  authority only as the bare host, or the host plus an all-digit port.

  ```lua
  local host, port = authority:lower():match("^([^:]*)(.*)$")
  if port ~= "" and not port:match("^:%d+$") then return false end
  return host == "127.0.0.1" or host == "localhost"
  ```

  Checked against 16 bypass forms: it refuses all of them. That covers the
  three glob forms, `[8989-8990]`, a space after the port, and every bypass
  already in the test. It keeps all 9 real loopback forms (including
  `LocalHost`, `#frag` and `?q=1`), and it makes the `@` check redundant. Add
  the glob URLs to the refused list at `tests/test_config.lua:76-78`. Task 6's
  plan has not started and should also pass `--globoff`, so that the URL curl
  gets is the URL that was checked. That is a second layer, not a substitute:
  acceptance items 4 and 5 belong to this task.

### 🟡 Should fix
- `tests/test_config.lua:76-78`: nothing pins the `@` guard at
  `config.lua:39`. The userinfo URLs in the test have no port, so their host
  (`127.0.0.1@evil.example`) already fails the equality test at line 41.
  Deleting `authority:find("@", 1, true)` keeps all 48 assertions green
  (mutation run on a scratch copy). Under that mutant,
  `http://127.0.0.1:8989@evil.example/v1` is loopback, because the host is the
  text before the first colon, and curl sends to evil.example. For the same
  reason, the comment at `config.lua:33-34` credits the userinfo refusal to the
  wrong line. Add a `:port@host` form to the refused list. It stays useful
  after the red fix, whichever line then does the refusing.
- `config.lua:61-63`: `backend` is stored without validation. The plan's
  interface says "A field that fails validation falls back to its default and
  produces a warning". D4 made the triple fall back together precisely to avoid
  a misleading error. Trigger: `backend: Anthropic`, `backend: claude`, or
  `backend: openai   # openai | libretranslate | anthropic` (Task 10's template
  line 180, once uncommented). `config.load` returns that string with 0
  warnings (measured). Task 6's plan maps an unknown adapter to `http_error`
  (task-06 line 230), so every Enter shows `✗ 翻译失败` and nothing in the log
  says why. No text is lost, because the error path keeps the draft. Fix: if
  `backend` is not one of the three adapter names, warn and fall back the
  triple, as the trust branch does.
- `config.lua:50-63`: the file is `ime_translate.yaml` and the plan calls the
  format a "flat YAML subset", but the parser silently misreads four YAML
  habits. None of them loosens trust, because each one fails closed. So this is
  strictness, not a leak. The problem is the silence: warnings reach the log
  only when `debug_log` is true (Task 9 plan lines 120-135). All measured:
  - Inline comments. Task 10's template puts `# ...` after the value on the
    very lines the user is told to uncomment.
    `allow_remote: true   # without this...` parses as false. The remote URL
    is then refused, with a warning telling the user to write the line they
    already wrote. `api_key_account: anthropic   # Keychain...` keeps the
    comment, so the Keychain lookup misses and every request becomes
    `auth_error`. `backend:` fails as described in the previous item.
  - Quotes. `base_url: "http://127.0.0.1:8989"` is refused as non-loopback and
    replaced with the default. `model: "claude-haiku-4-5"` and
    `api_key_account: "anthropic"` keep their quotes with 0 warnings, which
    gives an HTTP error or an auth error on every Enter.
  - Bools. Only lowercase `true` counts as true. `True`, `yes` and `"true"` are
    false with 0 warnings. That is safe for `allow_remote` and silent for
    `debug_log`.
  - Dropped lines. Any line that does not match `^%s*[%w_]+%s*:` is dropped
    with no warning: a UTF-8 BOM before the first key, or `base-url:`.

  Fix it on either side. The parser can strip a trailing whitespace-then-`#`
  comment and one layer of matching quotes, and warn on a bool that is neither
  `true` nor `false`. Or the parser stays strict, warns on a value that starts
  with a quote or contains ` #`, and the template's comments move to their own
  lines when Task 10 is revised for D4. Deferring to that revision is
  acceptable if a line here says so.

### 🟢 Suggestions
- `config.lua:57`: the bool parse is not pinned in the fail-closed direction.
  The mutants `out[k] = (v ~= "false")` and
  `(v:lower() == "true" or v == "yes")` both pass all 48 assertions. Under the
  first, `allow_remote: no` (or `off`, or `False`) enables cloud. Scenario: a
  later edit to accept YAML bool spellings takes that shape, and the suite
  stays green. One assertion pins it: `allow_remote: no` plus an https remote
  is still refused.
- `config.lua:52`: `%s` depends on the locale, which is Task 2's lesson. Under
  an `en_US.UTF-8` or `zh_CN.UTF-8` ctype it matches byte 0xA0. The trailing
  trim then cuts the last byte off a value that ends in a CJK character whose
  code point is 0x20 mod 64 (`你` is E4 BD A0). Measured: `prompt: X你` loads
  as 4 valid bytes under `C`, and as 3 bytes of invalid UTF-8 under
  `en_US.UTF-8`. It stays green because both conditions are narrow. Only a
  custom one-line prompt can end that way, and only after some Lua in the
  shared state sets a UTF-8 ctype, which Task 2's review found does not happen
  today. Using `[ \t]` in place of `%s` in the two whitespace runs removes it.

### Deviations from the plan
- `config.lua:32-42`, the `is_loopback` rewrite: an improvement, and it is
  explained in the file. The plan's defect is reproduced: the full test, run
  against the plan's `config.lua` extracted from the plan file, fails at
  `#34 not loopback without allow_remote: http://127.0.0.1.evil.example/v1`.
  The plan's own 33-assertion block passes on both versions.
- `tests/test_config.lua:23,73-87`: 15 added assertions (1 for
  `toggle_modifier`, 10 bypass forms, 4 loopback forms kept). Acceptance 1
  names no count. Plan step 4 says 33; the reason is recorded here.
- Plan line 206, `31` changed to `33`: correct. The plan's test block counts
  33 assertions against the plan's code.
- Everything else is byte-identical to the plan (diffed against both code
  blocks).

### What was walked
- Dimensions 1-3 and 5 do not apply. The diff has no `ctx:clear`, no
  `commit_text`, no processor, translator or session code, and no shell code.
  D1 is still open, but this diff touches none of the files D1 governs.
- Dimension 4: the module-level values are `DEFAULT_PROMPT`, `DEFAULTS`,
  `BOOLS` and `NUMS`, and none is written after load. Each call to `load`
  copies `DEFAULTS` into a fresh table, and every value is a scalar, so a
  caller that mutates its settings cannot reach `DEFAULTS`.
- §7.3: warnings name the key, never the value. A secret written as
  `api_key: sk-...` produces `unknown config key: api_key`, so config warnings
  cannot put a secret in the log. `api_key_account` is kept verbatim (#48).
- Dimension 7: the defaults match design §9, §8.2 and D4: `libretranslate`,
  `http://127.0.0.1:8989`, `""`, 1500, 2000, 0.2, 1024, false, `""`, false.
  The default prompt is byte-equal to §7.4's text block (278 bytes, compared
  programmatically). The `timeout_ms` comment says the value is the worst-case
  freeze, as §8.2 requires. D4's triple is (backend, base_url, model), while
  §9 calls base_url/model/prompt "the triple". Leaving the prompt out of the
  fallback is harmless under the libretranslate default, which sends no
  prompt.
- `is_loopback` against curl 8.7.1 on this machine. The sweep was exhaustive:
  `http://localhost` or `http://127.0.0.1`, followed by up to 4 tokens from
  `:8989 @ evil.invalid / ? # \ { } , [ ] %40 ; . :` and TAB. It produced
  7,822 URLs that `config.load` accepted as loopback although they contain
  `evil`. Each went through `curl -v` with `--resolve`, and curl targeted the
  evil host 0 times. The detector fires on the glob forms (checked), so the
  zero is real; the glob form needs 6 or more tokens, which is past the
  sweep's depth. Whitespace after the port (the inline-comment case) makes curl
  refuse the URL (exit 3), so nothing leaks. For curl, `?` and `#` end the
  authority, as they do for `is_loopback`.
- Strict, not unsafe: `[::1]`, `127.0.0.2`, `localhost.` and `HTTP://` are
  refused as remote. §7.2 names exactly `127.0.0.1` and `localhost`. curl tries
  `[::1]` and then `127.0.0.1` for `localhost` (measured), so a local server
  that listens only on IPv6 is still reachable as `localhost`. Refusing them
  costs nothing.
- Dimension 6: 18 mutants were run on a scratch copy.
  - Killed: timeout 3000, max_chars 666, `lower()` dropped, the plan's prefix
    match, a fallback of base_url alone, the https check dropped or loosened,
    the range check dropped, the unknown-key warning dropped, and the
    rejection warning dropped.
  - Survivors: the `@` guard (yellow) and two bool mutants (green). The
    `<=500` and `>=10000` boundary mutants survive with no consequence. The
    `#` comment skip is an equivalent mutant, because `#` can never match
    `[%w_]`. A `[^:@]` host is equivalent while the `@` guard stands.
  - Step 2's red state holds: with no `config.lua`, the test stops with
    `module not found`.
- Dimension 8: the diff makes no claim about librime or Squirrel. The
  `temperature` comment cites vendor behaviour and matches §7.7.
- Dimension 9: nothing that v1 excludes.
- `scripts/run_tests.sh` exits 0. `.githooks/pre-commit` over the staged
  content exits 0.

### Notes for Task 6's plan (outside this diff)
- Add `--globoff` (see the red item).
- curl uses `http_proxy` for loopback URLs. Measured:
  `http_proxy=http://127.0.0.1:1 curl http://127.0.0.1:18991/x` went to the
  proxy, and so did the same request to `localhost`. If Squirrel's environment
  ever carries a proxy, local translation goes through it. Passing
  `--noproxy '*'` when the `base_url` is loopback closes that.
- §7.2's "menu bar and log mark it cloud" has no implementer in plans 06-12
  (grep for cloud and menu bar). Whoever adds it needs this task's loopback
  verdict, which is a private function. Export it instead of deriving it a
  second time.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_config.lua` passes every assertion | ok | Re-run: `test_config: 48 assertions OK`. `scripts/run_tests.sh` exits 0 (config 48, decode 88, encode 10, state 17) |
| `timeout_ms` defaults to 1500 (not 3000) | ok | #4. The 3000 mutant is killed at #4 |
| `max_chars` counts characters, not bytes | ok for Task 5's part | `config.lua` only stores the ceiling: default 2000 (#5), `max_chars: 50` gives 50 (#14), range [1,5000] (#23, #24), and there is no byte arithmetic anywhere. The 666 mutant is killed. The counting itself is Task 6's (`utf8.len(text) or #text`, task-06 line 227). Task 6's test is NOT limited to 2001 characters: task-06 lines 108-110 require that 700 CJK characters (2100 bytes) are not `too_long`, and byte counting fails that because 2100 > 2000. Task 6's acceptance list does not name the property, though, and carrying it there is the user's call |
| `allow_remote=false` plus a non-loopback `base_url` is refused | **fails** | Holds for an https remote (#25-27) and for the prefix and userinfo forms (#34-42, even numbers). Fails for `http://localhost:8989{/,@evil.example/}` (see red) |
| `allow_remote=true` plus non-loopback `http://` is refused; `https://` is allowed | **fails** | https is allowed (#28). Plain-http remotes are refused (#29-31, and #35-43 odd numbers). The glob form still goes out over http (see red) |
| No `toggle_keycode` / `toggle_modifier` exist | ok | #11 and #12. A grep of `rime/` and `tests/` finds only those two assertions. Writing either key produces `unknown config key` (measured) |

### Verdict
1 red / 3 yellow: the task **cannot** be marked done until the red is fixed,
or until the user explicitly accepts it and that acceptance is recorded here.

---

### Author's response (Task 5, round 1)

- **Red — fixed.** Reproduced first: curl expanded `http://localhost:9{/,@evil.invalid/}`
  into two transfers, the second to `evil.invalid`, and `config.load` kept the
  equivalent `base_url` with 0 warnings. `is_loopback` now requires the authority
  to be exactly a host, or a host and a numeric port; userinfo and glob syntax
  both fail that, so the separate `@` test is gone. The three glob URLs, a
  `[1-2]` range and `127.0.0.1:8989@evil.example` are in the reject list and
  failed before the fix (#48). Hostile-URL probe after the fix: 11 URLs x 2 trust
  settings, 0 kept; 7 real loopback forms, 0 refused.
- **Yellow 1 — fixed** by the same assertion set: a `:port@host` URL is refused,
  and reverting the port check fails the suite.
- **Yellow 2 — fixed.** An unknown `backend` warns ("unknown backend", no value,
  per §7.3) and the whole triple falls back.
- **Yellow 3 — fixed in the parser**, not deferred: a `scalar()` step strips an
  inline comment (`#` starting the value or after whitespace), keeps a `#` inside
  quotes, removes one pair of surrounding quotes; a UTF-8 BOM before the first
  key is dropped; bools accept `true`/`false` in any case and anything else warns
  and keeps the default (fails closed).
- **Green 1 — taken**: `True` is asserted true; `yes` is asserted to leave
  `allow_remote` false and warn.
- **Green 2 — taken**: the parser uses `[ \t]` instead of `%s`; under a UTF-8
  ctype a prompt ending in U+4E20 now keeps its trailing 0xA0 byte (#65).
- **Mutation check**, one revert at a time: port check, backend validation,
  comment strip, quote handling, comment-only value, BOM, `== "true"` bools, a
  fail-open bool (`else out[k] = true`), and `%s` in the value trim — 9 of 9
  killed.
- **Acceptance 3**: the author's claim that Task 6's test cannot tell bytes from
  characters was wrong — its 700-character assertion does. Withdrawn.
- **Carried to Task 6's plan** (before it starts): `--globoff` on the curl
  command as a second layer, `--noproxy '*'` for a loopback `base_url`, and the
  §7.2 "cloud" marker that no plan implements.
- `test_config: 66 assertions OK`; `scripts/run_tests.sh` all PASS.

---

## Task 5: Config loading and validation — round 2

Range: `f84acb2..HEAD` is still empty; reviewed as `git diff f84acb2`. For
`config.lua` and `tests/test_config.lua` the staged content equals the working
tree. Not reviewed as Task 5 code: the unstaged D5 edits (`architecture.md`,
`decisions.md`, `upstream.md`, `task-10-wiring.md`), `progress.json` (ledger
state, consistent with `git log`), and the untracked `decide.lua` /
`tests/test_decide.lua` that appeared during this review from parallel work.
Stage only this task's files.
Time: 2026-09-21T07:56Z

### 🔴 Must fix
- None. The round-1 red is closed; the evidence is under "What was walked".

### 🟡 Should fix
- `rime/lua/ime_translate/config.lua:79-84`: an invalid bool keeps the
  **previous** value, not the default. The comment says "keep the default (both
  bools default to false, so this fails closed)", and so does the author's
  response. That holds only when the key appears once. Measured: the file
  `backend: openai`, `base_url: https://api.openai.com/v1`,
  `allow_remote: true`, then `allow_remote: no` (or `off`) loads with
  `allow_remote=true` and the openai backend, plus 1 warning. The warning reaches
  the log only when `debug_log` is true. Scenario: the user turns cloud on, and
  later adds `allow_remote: no` at the end of the file to turn it off, which is
  YAML 1.1's spelling of false. Every sentence keeps going to the third party.
  Duplicate keys are normal in this project's files: Task 10's template has
  `backend:` and `base_url:` in both the local and the cloud block, and the
  last one wins. This is a regression from round 1: the plan's
  `out[k] = (v == "true")` read `no` as false. Fix: `else out[k] = DEFAULTS[k]`
  before the warning. No assertion tells the two apart: the mutant that resets
  to the default passes all 66. Add a `true`-then-`no` case.
- `config.lua:72-75`: round-1 yellow 3 is only partly closed. Its "dropped
  lines" sub-item named `base-url:`, and the response does not mention it.
  A non-blank line that is not a comment and does not match the key pattern is
  still dropped without a warning. All measured, 0 warnings unless noted:
  - `backend： openai` with a full-width colon is dropped. The user of a
    Chinese IME is exactly who types one. The backend stays libretranslate.
  - `base-url: http://127.0.0.1:11434/v1` next to `backend: openai` is
    dropped. The openai adapter then posts to the libretranslate default
    `http://127.0.0.1:8989`, and every Enter shows `✗ 翻译失败`.
  - A YAML block scalar, the usual way to write a multi-line prompt:
    `prompt: |` stores the prompt as the one character `|`. Body lines without a
    colon are dropped. A body line such as `Output: English only` gives an
    unrelated `unknown config key: Output`. `prompt: >-` gives `>-` with no
    warning. The openai or anthropic adapter then sends `|` as the system
    prompt, so nothing tells the model to translate, and what it returns is
    committed.

  Fix: warn with the line number, never the content (§7.3: a line can be
  `api-key: sk-...`) for every non-blank, non-comment line that does not parse.
  Refuse a value of `|` or `>` (with an optional `-`, `+` or digit) with a
  warning and keep the default. Deferring to Task 10's D4 revision is
  acceptable if a line here says so.

### 🟢 Suggestions
- `tests/test_config.lua:101-103`: the unknown-backend test pins the backend,
  not the triple. The mutant that falls back only `backend` passes all 66.
  Under that mutant, `allow_remote: true`, `backend: claude`,
  `base_url: https://api.anthropic.com/v1` runs the libretranslate adapter
  against `https://api.anthropic.com/v1/translate`. That fails as `http_error`,
  the misleading error D4's triple rule exists to prevent. The later trust
  check still guards `base_url`, so trust does not loosen. Assert `base_url`
  and `model` too, using a remote https URL with `allow_remote: true`.
- `config.lua:42`: a whitespace-then-`#` in a plain value now ends it, as in
  YAML. Measured: `prompt: Keep hashtags like #tag intact.` loads as
  `Keep hashtags like`, with 0 warnings. Before this round the whole line was
  kept. The behaviour is correct YAML and quoting avoids it (checked). The
  cheapest guard is a comment line in Task 10's template: quote any value that
  contains ` #`.

### Round-1 items
| Item | Status | Evidence |
|---|---|---|
| Red, curl glob bypass | closed | Differential below: 0 of 37,367. All 5 red forms and 46 other hostile forms are refused under both trust settings |
| Yellow 1, `:port@host` | closed | `http://127.0.0.1:8989@evil.example/v1` is in the list (#52). Dropping the port check fails at #48, and so does putting back round 1's `@` guard in its place |
| Yellow 2, unknown backend | closed | `backend: Anthropic` and `backend: claude` fall back with 1 warning and no value in it. Task 10's template line `backend: openai   # openai \| libretranslate \| anthropic` now loads as `openai`. For the pinning gap, see green 1 |
| Yellow 3, YAML habits | partly | Inline comments, quotes, the BOM and bools are closed (#55-64). Silently dropped lines remain (yellow 2 above) |
| Green 1, bool strictness | closed | The fail-open mutant `else out[k] = true` dies at #63 |
| Green 2, `%s` | closed | The value-trim mutant back to `%s*$` dies at #65 (the `en_US.UTF-8` ctype exists here). The two remaining `[ \t]` runs before the value cannot eat a meaningful byte: 0xA0 cannot start a UTF-8 character |

### What was walked
- **curl differential, new `is_loopback`, curl 8.7.1.** The fuzzer draws a
  loopback prefix from 7 (localhost, 127.0.0.1 or LOCALHOST, over http or https,
  with or without `:18990`). It appends 1-8 tokens from 39: `{ } , [ ] - @ / ?
  # \ : ; . & =`, space, TAB, ` #`, `%40 %2F %23 %00`, both quote marks,
  `evil.invalid`, `@evil.invalid:18990`, and the composite globs
  `{/,@evil.invalid/}`, `{#,@evil.invalid}`, `{?,@evil.invalid}`,
  `{,@evil.invalid}` and `[1-2]`. One value in six is wrapped in double quotes.
  Each value goes through `config.load` (`backend: openai`, no
  `allow_remote`). When the backend survives (loopback) and the loaded
  `base_url` contains `evil`, the fuzzer runs Task 6's exact command shape
  through `/bin/sh`. That is `json.shq(base_url .. "/chat/completions")`, no
  `--globoff`, plus `-v`. It then looks for `evil` in curl's host lines. With
  no `--resolve`, a `.invalid` name always fails DNS, so any attempt to reach
  it shows up.
  - Calibration: the same fuzzer against round 1's `is_loopback` (the `@`
    check in place of the port check) finds 453 of 3,628 in 20,000 values.
  - New code: 8 seeds × 100,000 values. 108,846 are accepted as loopback, and
    37,367 distinct accepted URLs contain `evil`. curl reached an evil host
    **0** times.
- **Why the zero is structural and not luck.** An accepted value is `http://`
  or `https://`, then exactly `127.0.0.1` or `localhost` in any case, then
  optionally `:digits`, then either the end or one of `/ ? #`. No `{ [ @ \ %`
  and no whitespace can come before that terminator. So every URL curl gets
  from glob expansion keeps the literal scheme, authority and terminator, and
  curl ends the authority at the same `/ ? #`. That is measured in round 1 and
  again here, for example `{?,@…}` and `#{/,@…}` after the port. The adapters
  append `/chat/completions`, `/translate` and `/messages` (task-06 lines 157,
  180, 193). All start with `/`, so appending cannot extend the authority.
  - Locale: `%d` and `lower()` were checked under `C`, `en_US.UTF-8`,
    `zh_CN.UTF-8` and `en_US.ISO8859-1`. No byte of 0x80 or above matches
    `%d`, and none lowercases into ASCII.
- **Named forms**, each under both trust settings (all refused, which is
  fine):
  - whitespace inside the authority (space, TAB)
  - `%6c`, `%2e`, `%40` and `%00` in the host
  - `[::1]` and `[::ffff:127.0.0.1]`
  - `localhost.` and `localhost.:port`
  - `127.1`, `127.0.1`, `2130706433`, `0x7f000001`, `017700000001`,
    `0177.0.0.1`, `127.0.0.01` and `0x7f.0.0.1`
  - `HTTP://`, `http:/`, `http:///` and `http:\\`
  - `:` with no digits, `:18990:1` and `::18990`
  - a NUL before the terminator
  - `;@` and `\@` after the port

  CR and LF cannot reach a value, because lines split on both. Four accepted
  forms were also run through curl, with 0 attempts on an evil host:
  - A NUL after the terminator (`http://localhost:18990/\0@evil.invalid/`).
    `io.popen` truncates the command at the NUL, so the single quote is never
    closed and `sh` exits with a syntax error. No request is made.
  - `:0` and `:99999999999`: curl refuses both locally.
  - `/../@evil.invalid`: the host stays localhost.
- **Parser regressions** (measured):
  - `http://127.0.0.1:8989/v1#frag` is kept, and so is `model: foo#bar`.
  - `model: "a # b"  # note` gives `a # b`.
  - `model:   # set later` keeps the default.
  - CRLF and CR-only files parse the same as LF.
  - Unterminated or doubled quotes on `base_url` start with `"`, so they are
    refused.
  - `allow_remote: "true"`, `TRUE` and `true   # comment` are true.
    `false # true`, `# true` and `yes` stay false.
  - Nothing new becomes loopback or `allow_remote=true`, except the
    duplicate-key case in yellow 1.
- **Dimension 6**, 17 mutants of my own:
  - Killed: the port check dropped (#48), the port check without `$` (#48),
    the authority also stopping at `@` (#38), the value trim back to `%s` (#65),
    a comment without the whitespace rule (#60), the BOM strip dropped (#61),
    the backend check dropped or case-folded (#53), the fail-open bool (#63),
    and `lower()` dropped (#46).
  - Harmless or stricter survivors: `^:%d*$`, the authority ending only at
    `/`, a leading `%s*`, and quoted values ignoring trailing junk.
  - Real survivors: the backend-only fallback (green 1) and the
    reset-to-default bool (yellow 1, which is its fix).
  - One of my early runs reported two mutants alive. That was a wrong module
    path in my harness, which ran the real module. Re-run with an absolute
    path, both die at #48.
- **Design.**
  - §7.2: exactly `127.0.0.1` and `localhost`, and https is enforced for
    non-loopback.
  - §7.3: every new warning names a key or nothing, never a value.
  - §9: the key set is unchanged, with no toggle keys.
- **Dimension 4.** `BACKENDS` is read-only and `scalar()` is pure.
- **Dimensions 1-3, 5 and 8** do not apply. There is no `ctx`, commit or shell
  code. The `%s` and glob comments cite measurements, not librime.
- **Commands.** `scripts/run_tests.sh` exits 0. `.githooks/pre-commit` over the
  staged content exits 0. Its unit-test step also ran the untracked
  `test_decide.lua` (27 OK), because it tests the working tree.

### Notes outside this diff
- Task 6's plan does not have `--globoff` or `--noproxy` yet: a grep of
  `task-06-backend.md` finds neither. The response says they were carried
  there. With this `is_loopback`, `--globoff` is defense in depth.
- Task 10's `install.sh` (plan line 303) reads the **first** `backend:` line
  and takes awk's `$2`. `config.load` takes the **last** line and strips quotes
  and comments. So `backend: "libretranslate"` gives `install.sh` the value
  `"libretranslate"`, quotes included. That falls to the `*)` case, which
  installs `apfel-serve`, and D4 says apfel cannot run on this machine. Settle
  it in the D4 revision of Task 10.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_config.lua` passes every assertion | ok | `test_config: 66 assertions OK`; `scripts/run_tests.sh` exits 0 |
| `timeout_ms` defaults to 1500 (not 3000) | ok | #4 |
| `max_chars` counts characters, not bytes | ok for Task 5's part | The ceiling is stored with no byte arithmetic (#5, #14, #23, #24). The counting is Task 6's |
| `allow_remote=false` plus a non-loopback `base_url` is refused | ok | #25-27, even numbers #34-42, #48-52, and the sweep (0 of 37,367). When a later invalid spelling follows `allow_remote: true`, the effective value stays true (yellow 1) |
| `allow_remote=true` plus non-loopback `http://` is refused; `https://` is allowed | ok | #28 is allowed. #29-31 and odd numbers #35-43 are refused. All 51 hostile forms are refused with `allow_remote: true` too |
| No `toggle_keycode` / `toggle_modifier` exist | ok | #11, #12 |

### Verdict
0 red / 2 yellow: no red, clear to close. Fix each yellow, or defer it with a
one-line reason recorded here.

---

### Author's response (Task 5, round 2)

- **Yellow 1 — fixed.** An invalid bool now resets the key to its default and
  warns, so `allow_remote: true` then `allow_remote: no` leaves cloud off (#65).
  The round-1 fix had introduced this; the plan's `(v == "true")` read `no` as
  false.
- **Yellow 2 — fixed.** Lines are counted, blank ones included; a line that does
  not parse warns `line N not understood` (number only, §7.3), which covers the
  full-width colon and `base-url:` (#66-68). A value starting with `|` or `>`
  is a YAML block scalar: refused, default kept, warned (#69-70). A quoted value
  starting with `|` is not a block scalar and is kept (#71) — pinned because a
  first draft of this fix dropped it silently.
- **Green 1 — fixed.** An unknown backend is asserted to take `base_url` and
  `model` down with it (#72-73).
- **Green 2 — deferred to Task 10**: `#tag` in an unquoted prompt is a comment,
  which is correct YAML. Task 10's template should quote the prompt or say so.
  Not edited now: `task-10-wiring.md` carries another session's uncommitted D5
  edits.
- **Correction to round 1's response**: `--globoff`, `--noproxy` and the §7.2
  cloud marker were "carried to Task 6" in the sense of *to be applied before
  Task 6 starts* — they are not in `task-06-backend.md` yet. Task 10's
  `install.sh` reading `backend:` with awk (first line, quotes kept) is also
  noted for Task 10's revision.
- **Checks after the fix**: mutation check of the round-2 fixes, 6 of 6 killed
  (bool reset, line warning, block scalar, backend-only fallback, the quoted-`|`
  re-match, BOM on line 1). Hostile-URL probe: 8 URLs x 5 quote/comment forms
  x 2 trust settings, 0 kept. `test_config: 75 assertions OK`.

---

## Task 8: Pure-function key decisions — round 1

Range: `f84acb2..HEAD` holds only Task 5's commit `d1fcf34` and none of Task 8.
Task 8 is staged, not committed. It was reviewed as
`git diff --cached -- rime/lua/ime_translate/decide.lua tests/test_decide.lua`.
For both files the staged content equals the working tree. Not reviewed: the
unstaged D5 edits (`architecture.md`, `decisions.md`, `upstream.md`,
`task-10-wiring.md`). A grep shows they change nothing in §5.2, §6.2 or the
key handling. Also not reviewed: `progress.json`, which is ledger state.
Time: 2026-09-21T08:39Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_decide.lua:35` (also lines 49 and 57-59): the test cannot fail
  for a wrong keycode or mask.** The key identities come from the module under
  test: `RET, ESC = decide.RETURN, decide.ESC`, plus `decide.SHIFT`. Each of
  these mutants of `decide.lua:7-8` passes all 27 assertions (measured in a
  scratch copy):
  - RETURN and ESC swapped
  - `ESC = 0xFF1D`
  - `RETURN = 0xFF8D`
  - `SHIFT = 0x2` (that is kLockMask)
  - `SHIFT = 0x10`

  Scenario: a later edit to line 7 mistypes `0xFF1B`, for example while adding
  the R15 mask below. Esc in the result phase then falls into the catch-all and
  goes to the native chain. fluid_editor's `CancelComposition` wipes the whole
  draft and commits nothing, which is exactly what spike S11 row 5b measured.
  `test_decide` stays green.

  Also unpinned: Esc with a modifier. In result or error, the current code
  returns `clear_display` for Esc whatever the modifier. That is correct.
  librime's `Editor` runs its keymap with `FallbackOptions::All`, and its
  IgnoreShift fallback maps Shift+Escape onto `CancelComposition` (source
  reading: `key_binding_processor_impl.h`, librime master). Adding
  `key.modifier == 0` to line 33 would match the Enter branch's style, and that
  mutant passes 27/27. Shift+Esc in the result phase would then wipe the draft.

  Fix:
  - Assert the measured values as literals: `decide.RETURN == 0xFF0D` (spike
    report, "Return keycode 65293"), `decide.SHIFT == 0x1` (S14,
    `key=0x61 mod=0x1`) and `decide.ESC == 0xFF1B` (XK_Escape). Or build the
    test keys from literals.
  - Add Shift+Esc in the result phase → `clear_display`.

  This was considered for red, as a test that cannot fail. It stays yellow
  because the three constants in this diff are correct. They were checked
  literally, so nothing wrong ships. The gap is that the next edit to them is
  unprotected.
- **`rime/lua/ime_translate/decide.lua:20,28`: Caps Lock (R15). Nothing masks
  it, and decide is the place to do it.** This answers observation (a).
  - **What it does.** Squirrel sets kLockMask (0x2) on every key while Caps Lock
    is on. That is F12, and the spike measured it: `mod=0x2` on Return. Enter
    with a draft then misses both `== 0` and `== M.SHIFT`. The result is `noop`
    in idle and `invalidate_and_pass` in result or error. The key passes through
    unhandled. fluid_editor binds `{Return, 0}` only, and KeyBindingProcessor has
    no Lock fallback (source reading). The spike's R15 run measured the outcome:
    the application's newline replaced the marked text. In a chat box that is a
    send with the message eaten.
  - **Reachability today.** Not reachable under the stock
    `ascii_composer/switch_key/Caps_Lock: clear` with `good_old_caps_lock: true`
    (source reading of `ascii_composer.cc` `ProcessCapsLock`):
    - Pressing Caps Lock with a draft open runs `SwitchAsciiMode` with the
      clear style, so the draft is gone first.
    - While Lock is on, every key carrying the Lock bit is rejected, so no draft
      can form.
  - **When it becomes reachable.** Setting the translation schema's `Caps_Lock`
    to `noop` or `inline_ascii` makes it reachable. That is the obvious fix for
    the spike's other candidate, "Caps Lock clears the draft". So R15 comes back
    as soon as that one is fixed.
  - **Nobody owns the mask.**
    - risks.md §12.1 R15 puts it in the glue.
    - The spike report's "Constants later tasks need" gives the consumer as
      "Task 8 — mask to Shift/Control/Alt/Super before `decide`". upstream.md
      §15.1 says the report wins where the two disagree.
    - Task 9's plan, line 141, copies `modifier = key.modifier` raw.

    As the plans stand, no task masks.
  - **Why decide and not the glue.**
    - Here it is unit-testable. The glue's only planned test is a load smoke
      test, so a mask there would ship untested.
    - decide already owns the modifier semantics: the Shift escape hatch, and
      "other modifiers take no commit path".
    - Masking in the glue as well costs nothing.
  - **Fix.**
    - Compare `key.modifier & (0x1 | 0x4 | 0x8 | 1 << 26)`, that is Shift,
      Control, Alt and Super, the set the spike report names.
    - Add tests: Return+Lock gives `translate`, `commit_translation` or
      `commit_draft` by phase, and Shift+Return+Lock gives `commit_draft`.
    - Add one sentence recording the deviation from the plan.
  - **Deferring** is acceptable only if Task 9's plan line 141 is amended to
    mask and the reason is recorded here.
- **`decide.lua:7,20,28`: keypad Enter is "any other key".**
  - **Scenario.** On an external keyboard, the user presses the keypad Enter
    with a draft open.
  - **What arrives.** Squirrel maps `kVK_ANSI_KeypadEnter` to `XK_KP_Enter`
    (0xFF8D). That is a source reading of `MacOSKeyCodes.swift` on master. The
    mapping sits in the same `keycodeMappings` table as keypad `/` and `.`, and
    the spike measured those arriving as `0xffaf` and `0xffae` on 1.1.2 (S14).
  - **What decide does.** It returns `noop` in idle and `invalidate_and_pass` in
    result or error.
  - **What the native chain does.** Outside ascii mode, nothing binds it (source
    readings: F1's fluid_editor binds `XK_Return` only, the prelude's
    `key_bindings.yaml` has no `KP_Enter`, and librime master's
    `ascii_composer.cc` handles `KP_Enter` only when `ascii_mode` is on).
  - **Consequence.** The application receives Enter while the draft is marked.
    This is derived, not measured for `KP_Enter`: the spike saw the same pattern
    for Return+Lock (R15) and for keypad `/` and `.` (S14). The newline replaces
    the draft. A keypad-Enter user never gets a translation, and in a chat app
    sends with the draft eaten.
  - **Fix.** §5.2 says "Enter" and names no keysym. If the user reads that as the
    key, fix it here: treat `0xFF8D` as Enter in both branches, with tests.
    Otherwise open it via `/design-review` and put keypad Enter in Task 11's
    compatibility matrix. Record the choice either way.
- **`decide.lua:33,41`: Control+g and Control+bracketleft get around the
  result-phase Esc intercept that S11 row 5b calls for.** decide intercepts
  `XK_Escape` correctly. But the default key_binder's `emacs_editing` maps
  both chords to Escape (`{ when: composing, accept: Control+g, send: Escape }`).
  The path, as derived from source readings (librime master `key_binder.cc`
  `PerformKeyBinding`, `engine.cc` `ProcessKey`, and rime-prelude
  `key_bindings.yaml`) and Task 9's plan:
  1. Control+g arrives in the result phase. The catch-all returns
     `invalidate_and_pass`.
  2. The glue runs `session.clear`, which sets the phase to idle, and returns
     kNoop.
  3. key_binder sends Escape. The Escape goes back into `ProcessKey` from the
     first processor.
  4. The Lua processor now sees idle, so decide returns `noop`.
  5. fluid_editor's `CancelComposition` clears the whole draft and commits
     nothing.

  Not measured. Corroboration: the spike measured 30 key_binder bindings in the
  built schema. That is the prelude's 28 (14 `emacs_editing`, 4 paging,
  10 `numbered_mode_switch`) plus the two Control+Shift+T bindings, so
  `emacs_editing` is in there. Plain Esc keeps the draft, but its emacs alias
  deletes it.

  Fix: this may not belong in decide. Either decide treats those two chords as
  Esc in result and error, which copies key_binder config into decide, or
  Task 10 drops them from the translation schema's `key_binder`. Defer with a
  line naming which.

### 🟢 Suggestions
- **`tests/test_decide.lua:85-92`: the purity check covers one field.** Each of
  these mutants passes 27/27:
  - writing `key.keycode`
  - writing `key.release`
  - keeping `M.last_phase` or `M.calls` at module level (the shape of the
    dimension-4 red line)
  - writing `state.BUSY`

  decide is pure today. Its bytecode (lines 17-43, `luac -l -l`) has no `CALL`,
  no `SETTABUP` and no `SETUPVAL`, and `SETFIELD` only on the table it
  returns. The only foreign code it can run is an `__index` metamethod on the
  caller's key. So this only protects later edits. Suggestion: snapshot
  `pairs(key)`, `pairs(decide)` and `pairs(state)` before and after a batch of
  calls and compare them, the same way Task 4 pinned its export set.
- **The catch-all is pinned by nine hand-picked keys.** The sweep behind
  acceptance 3 is not committed. These mutants pass 27/27:
  - exempting the modifier keysyms 0xFFE1-0xFFEE from the catch-all, which is
    the obvious "fix" for observation (b)
  - Enter with an empty draft in the result phase returning
    `commit_translation`, which would commit the stale translation of a draft
    the user deleted
  - Shift+Enter or Esc with an empty draft in result

  The empty-draft cases are reachable only if check 2 fails to clear a stale
  phase first. Suggestion: commit a compact sweep, for example all 65,536
  keycodes × {0, Shift, Control, Lock} × result and error, asserting
  `invalidate_and_pass` off Return and Esc. Also pin the empty-draft rows. My
  6.3M-call sweep runs in 1.2 s, so a quarter of it costs nothing.

### Deviations from the plan
- `tests/test_decide.lua` is byte-identical to the plan's first code block.
- `decide.lua` differs from the plan only in comment lines 13-14. The plan had
  `engine:commit_text(translation)` / `engine:commit_text(Chinese draft)`; these
  now read "the processor commits …". The change was forced. Reproduced: the
  plan's body fed to `checks_lua_invariants` exits 1 ("decide.lua contains
  commit_text — the commit exit must be unique"), and the staged body exits 0.
  Meaning is unchanged, so this is neutral.

### What was walked
- **Design §5.2, row by row.** No mismatch:
  - Enter: idle with a draft gives `translate`, and idle with an empty draft
    gives `noop`. Result gives `commit_translation` and error gives
    `commit_draft`.
  - Shift+Enter gives `commit_draft` in all three phases.
  - Esc: `noop` (native) in idle, and `clear_display` in result and error.
  - Every other key: `noop` in idle and `invalidate_and_pass` otherwise.
- **§6.2 check 1** lives here, and the sweep confirms it (acceptance 3 below).
- **Esc in the result phase (S11 row 5b).** Intercepted: `clear_display`
  returns kAccepted in Task 9's plan. It is intercepted with any modifier, which
  is the safe side (yellow 1). The gap is the emacs alias (yellow 4).
- **Dimension 1.** decide has no `ctx:clear`. It returns `commit_draft` and
  `commit_translation` only when the draft is not empty. Task 9's plan commits
  before it clears in both branches. `clear_display` keeps the draft by
  contract. The only draft loss next to decide is native behaviour after
  `invalidate_and_pass` or `noop` (yellows 2-4).
- **Dimension 2.** No `commit_text` here; see the hook result under
  "Deviations from the plan". decide produces no candidate.
- **Dimension 3 and D1.** D1 is open and blocks Tasks 7 and 9, not 8. Both of
  its options change how the translation is shown and how staleness is
  detected, not the key table. Spike rows 5a and 5b (prompt mode) agree with
  decide's actions.
- **Dimension 4.** Module level holds `M` (three numbers and one function) and
  the `state` upvalue. No value here would differ per input box.
- **Dimension 5.** No shell.
- **Dimension 7.** The constants were checked literally:
  - `0xFF0D` is the measured 65293.
  - `0x1` is the measured Shift bit.
  - `0xFF1B` is XK_Escape. Squirrel master maps `kVK_Escape` to it (source
    reading; the keysym was not measured on this machine).
- **Dimension 8.** The comments claim nothing about the engine beyond
  "noop = later processors". The spike measured that kNoop passes every key on.
- **Dimension 9.** No toggle and no pre-translation.
- **Dimension 6: 31 mutants, 14 killed.** Killed:
  - release check dropped or moved
  - Enter ignoring modifiers
  - the empty-draft check dropped
  - error-phase Enter changed to `commit_translation` or `translate`
  - Shift+Enter with an empty draft
  - Esc only in result, or Esc also in idle
  - catch-all only in result, or enumerating printable and tested keys
  - result-phase Enter changed to `translate`
  - Shift+Enter in result committing the translation
  - idle invalidating

  The 17 survivors:
  - five constant mutants, `RETURN = 0xFF8D`, and the Esc-modifier mutant
    (yellow 1)
  - the Lock mask (yellow 2, the fix itself)
  - four purity mutants (green 1)
  - the modifier-keysym exemption and three empty-draft mutants (green 2)
  - Shift+Control+Return as `commit_draft`, which is harmless: it commits
    Chinese instead of fluid_editor's native `CommitComment`

  Step 2's red holds: without `decide.lua` the test stops at line 2 with
  `module 'ime_translate.decide' not found`.
- **Observation (b): a bare modifier press voids the translation. It does not
  matter, so it is not a finding.**
  - Squirrel does forward modifier presses to librime (source reading:
    `SquirrelInputController.swift`, the `.flagsChanged` branch). This matches
    the spike's measured Super mask and S14's phantom `a` with the Shift bit.
  - Cmd shortcuts: a Cmd keyDown never reaches librime
    (`if modifiers.contains(.command) { break }`), so only the Super press
    itself voids the translation.
  - Shift+Enter: the Shift press voids the translation first, then Shift+Return
    in idle gives `commit_draft`. That is the same outcome §5.2 specifies.
  - What is lost is a displayed translation, never text. The draft is intact,
    and getting the translation back costs one Enter and one backend call
    (local P95 21 ms, S8).
  - Exempting modifier keysyms is exactly the key enumeration §6.2 rejects. An
    unnecessary void is a retry, while a stale translation is the bug class the
    catch-all exists to prevent.
- **Upstream readings for this round.** Squirrel master, librime master and
  rime-prelude master, fetched 2026-09-21. These are not the installed
  Squirrel 1.1.2 or librime 1.16.0. librime master's `ascii_composer.cc` has
  been visibly restructured. Re-read the Caps Lock reachability claim in
  yellow 2 against 1.16.0 before relying on it.
- **Commands.**
  - `lua tests/test_decide.lua` exits 0.
  - `scripts/run_tests.sh` exits 0: config 75, decide 27, decode 88, encode 10,
    state 17.
  - `.githooks/pre-commit` over the staged content exits 0, and `git status` is
    unchanged afterwards.

### Notes outside this diff
- However yellow 2 is settled, two of these three will disagree afterwards:
  risks.md §12.1 R15 ("one line in the glue"), the spike report's constants row
  ("Task 8"), and Task 9's plan line 141 (raw modifier). They need to be brought
  into line before Task 9 starts, or in Task 12. This review does not edit them.
- For Task 9's review: decide assumes `key.release` is a boolean. The spike
  measured that the librime KeyEvent's `release` is a function. Passing the
  KeyEvent itself would make line 18 truthy for every key, and the IME would
  silently never translate. Task 9's plan line 141 does it right
  (`key:release()`).

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_decide.lua` passes every assertion | ok | `test_decide: 27 assertions OK`; `scripts/run_tests.sh` and `.githooks/pre-commit` exit 0; Step 2 red reproduced |
| Covers Enter in all three phases, Shift+Enter, Esc, any other key, release events, Enter with modifiers | ok | #5-7, #8-10, #14-16, #17-25, #1-2, #11-13 |
| Any other key is always `invalidate_and_pass` | ok | Line 41 has no keycode condition. Independent sweep: 65,536 keycodes × 12 modifier sets (including Lock, Super, Shift+Lock and the release bit) × 2 draft states × result/error = 3,145,728 calls. Of those, 3,145,672 are not Return, Shift+Return or Esc, and 0 of those return anything but `invalidate_and_pass`. The author's figure of 1,572,864 is the whole 65,536×6×2×2 product; excluding Return, Shift+Return and Esc leaves 1,572,832. The conclusion stands. Only code reading and an uncommitted sweep protect it (green 2) |
| There is no toggle branch | ok | Across idle, result, error and busy the action types are exactly `clear_display`, `commit_draft`, `commit_translation`, `invalidate_and_pass`, `noop` and `translate`. No `toggle` in `decide.lua` |

### Verdict
0 red / 4 yellow: no red, clear to close. Fix each yellow, or defer it with a
one-line reason recorded here. Yellows 2-4 each need a named owner, because the
fix may land outside `decide.lua`.

### Author's response (Task 8, round 1)

- **Yellow 1: fixed.**
  - The test builds its keys from literals, not from the module:
    - Return `0xFF0D` and Esc `0xFF1B`
    - keypad Enter `0xFF8D`
    - Shift `0x1`, Lock `0x2`, Control `0x4`, Alt `0x8` and Super `1 << 26`

    It also asserts the module's constants against those literals.
  - Added tests: Shift+Esc in result and Control+Esc in error both give
    `clear_display`.
  - `decide.lua` now carries a comment on why Esc accepts any modifier. The
    code did not change.
- **Yellow 2: fixed, in decide.**
  - `decide` compares `key.modifier & M.MODIFIERS`, where the mask is
    Shift | Control | Alt | Super (the spike report's set). Lock, and any bit
    `decide` does not name, is dropped before any comparison.
  - Tests:
    - Return+Lock in each phase, and with an empty draft
    - Shift+Return+Lock
    - Control+Return+Lock and Super+Return, which still take no commit path
  - The three documents were brought into line:
    - risks.md R15: the table row, and an update to §12.1.
    - Task 9's plan at line 141: a comment saying the modifier goes in raw
      because `decide` masks it.
    - The spike report's constants row already named Task 8.
  - The R15 update keeps the second path separate. Pressing Caps Lock itself
    discards the draft through the inherited `Caps_Lock: clear`. That is a source
    reading, not observed, and it is still open; this fix does not touch it.
- **Yellow 3: fixed, in decide.** `XK_KP_Enter` (`0xFF8D`) takes both Enter
  branches.
  - This reads §5.2's "Enter" as the key, not as one keysym. Under the other
    reading, keypad Enter with a draft open reaches the application, which
    replaces the draft. That breaks the §6.3 red line.
  - Tests: all three phases, an empty draft, Shift, and Lock.
  - Not measured. That Squirrel sends `0xFF8D` for this key is the review's
    source reading. Keypad Enter goes on the list for Task 10's revision below,
    so a person checks it at the machine.
- **Yellow 4: deferred to Task 10.**
  - This processor sees Control+g and Control+bracketleft before `key_binder`
    does. The only fixes inside `decide`:
    - copy `key_binder`'s configuration into it
    - and break acceptance item 3 ("any other key is always
      `invalidate_and_pass`")

    I tried that version and backed it out.
  - The path cannot be reached before Task 10, because nothing is wired until
    then.
  - `test_decide` now pins Control+g in result to `invalidate_and_pass`, so any
    change here has to be deliberate.
  - **Owner: Task 10's schema.** Drop the two `Escape` bindings from the
    translation schema's `key_binder`, or do not import `emacs_editing`, or
    accept the loss knowingly.
- **Green 1: done.** Purity is checked per call.
  - 320 calls: 4 phases × 5 keys × 8 modifier sets × 2 draft states.
  - Each call gets a fresh key table, snapshotted before and after the call.
  - The module table and `state` are snapshotted around the whole batch.
- **Green 2: done.**
  - A committed sweep: 65,536 keycodes × 8 modifier sets (0, Shift, Lock,
    Shift|Lock, Control, Alt, Super, Control|Lock) × 2 draft states × 3 phases.
  - It skips only the rows §5.2 names: 3,145,632 calls, 0.4 s.
  - The modifier keysyms 0xFFE1-0xFFEE are included on purpose.
  - For Return and keypad Enter alike, Enter and Shift+Enter with an empty draft
    in result and error are pinned to `noop`.
- **Mutation check.**
  - 22 mutants, all killed; the unmutated control passes. They are:
    - the round's 17 survivors, where they still apply
    - Esc accepting only an unmodified key
    - mutants of the new code: the mask keeping Lock, the mask dropping Super,
      and keypad Enter dropped
    - writes to the key with a changed value
  - The control runs first for a reason. An earlier run in a scratch directory
    reported every mutant killed. In fact `lua` never launched: asdf's shim finds
    no version outside the repository.
  - Same-value writes to the key are equivalent mutants, so they are not counted.
- **Deviations from the plan**, all in this response:
  - `decide.lua`: the mask, keypad Enter, and comments.
  - `test_decide.lua`: literal keys, and the tests above. 60 assertions, up
    from 27.
  - Acceptance is unchanged.
- **For Task 10's revision.** Not written into `task-10-wiring.md`, because
  another session's uncommitted D5 edits hold it. Two items:
  - yellow 4, above
  - a keypad Enter check in Step 6, which feeds Task 11's compatibility matrix

---

## Task 6: Backend adapters — round 1

Range: `d1fcf34..HEAD` is empty, because Task 6 is staged, not committed. It
was reviewed as
`git diff --cached -- rime/lua/ime_translate/backend.lua tests/test_backend.lua`.
For both files the staged content equals the working tree. Not reviewed: the
staged Task 8 files (`decide.lua`, `tests/test_decide.lua`), the unstaged D5
edits from another session (`architecture.md`, `decisions.md`, `upstream.md`,
`task-10-wiring.md`), and `progress.json`, which is ledger state.
Time: 2026-09-21T09:28Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`rime/lua/ime_translate/backend.lua:51-55` (also `:28-31`): `translate`
  raises instead of returning an error code.** Measured on the staged file:
  - The openai `parse` indexes without type checks. Six HTTP 200 bodies raise
    `attempt to index a number value` (or `a boolean value`) at line 52 or 53:
    `{"choices":1}`, `{"choices":true}`, `{"choices":[1]}`,
    `{"choices":[true]}`, `{"choices":[{"message":1}]}` and
    `{"choices":[{"message":true}]}`. The anthropic and libretranslate
    adapters type-check, and none of the shapes tried against them raises.
  - `decimal2` raises for a temperature too large for an integer.
    `temperature: 1e20` loads with 0 warnings (`config.load` does not bound
    it), and line 30 raises `bad argument #2 to 'format' (number has no
    integer representation)`. The plan's `tostring` gave `1e+20` here, a valid
    JSON number that a vendor would answer with a 400 (`http_error`). The input
    is contrived. It is listed because deviation (d) introduced it.
  - Consequence: §7.1's contract is `ok, translation_or_errcode`, and Task 9's
    plan calls `backend.translate` with no `pcall` (task-09-glue.md line 147).
    What librime-lua does with a processor that raises is **unverified** this
    round: its `lua_gears.cc` was not re-read, because the fetch from GitHub
    timed out. If it logs and returns kNoop, as I recall, Enter falls through
    to fluid_editor's `{XK_Return, 0}` binding, which is `CommitComposition`
    (source reading, librime master `editor.cc:194`). The Chinese draft is
    then committed with no `✗` reason, in place of §8.1's error phase. Task 9's
    log line (task-09 line 151) never runs, so nothing records why.
  - Fix: call `pcall(ad.parse, data)` in `translate` and map a raise to
    `empty`, or give the openai `parse` the type checks the anthropic adapter
    already has. Make `decimal2` total, for example by refusing
    `math.abs(x) >= 1e6`. Add one assertion per shape.
- **`backend.lua:122`: curl reads the user's `~/.curlrc`, because the command
  has no `-q`.** curl looks for `$CURL_HOME/.curlrc`, then
  `$XDG_CONFIG_HOME/curlrc`, then `$HOME/.curlrc`, and without `HOME` it falls
  back to `getpwuid` (curl 8.7.1 man page, under `-K`). So the curl that
  Squirrel starts reads it too. Measured through `real_runner` against a local
  listener, with `CURL_HOME` pointing at a scratch directory:
  - `include`: every successful translation becomes `bad_json`, because the
    response headers are prepended to the body.
  - `fail`: a 401 becomes `http_error` instead of `auth_error`, so the user
    reads `✗ 翻译失败` where `✗ 密钥无效` was due.
  - `retry = 2`: a timeout with `timeout_ms` 1500 freezes for 7.63 s, against
    1.57 s without the file. That breaks §8.2's "this number IS the worst-case
    freeze", which the comment at lines 111-113 cites.

  With `curl -q` as the first argument, all three came back as success,
  `auth_error`, and `timeout` at 1.56 s. No `~/.curlrc` exists on this machine
  today. The trigger is the user adding one for shell work. There is a
  trade-off: `-q` also drops a `proxy =` line that a cloud user might rely on,
  since Squirrel is started by launchd and does not see shell variables. If
  cloud through a proxy is wanted, it should be an explicit config key rather
  than an accident of `~/.curlrc`, and that is a design question. Fix:
  `"curl", "-q", ...` (it only works as the first argument), plus an assertion
  that the command starts with `curl -q `.
- **`tests/test_backend.lua`: `real_runner` has no test.** Every assertion uses
  a fake runner, and a fake that returns `(body, http_code, exit_code)` cannot
  contradict the contract it encodes. `conn_refused`, `timeout` and every
  code derived from an HTTP status depend on `real_runner`'s parsing.
  - The mutant `local exit_code = ok and 0 or -1` (line 14) passes 78/78.
    Against a closed port it turns `conn_refused` into `http_error`, measured
    on a scratch copy; the staged code gives `conn_refused`. `timeout` is lost
    the same way. The user reads `✗ 翻译失败` instead of `✗ 翻译服务未启动`.
  - A mutant that skips the `-w` split at line 15 also passes 78/78. It would
    make every response `bad_json`.
  - The author's integration run covers this today, and nothing keeps it
    covered.

  Fix: `real_runner` takes any shell command, so it can be tested without a
  network. Measured: `printf '{"a":1}\n401'` gives `{"a":1}`, 401, 0.
  `printf partial; exit 28` gives exit 28, and `exit 7` gives exit 7. A body
  with inner newlines followed by `\n200` splits at the last newline.
- **`backend.lua:89-99` and `:51-55`: a truncated translation is returned as a
  success.** Measured: the body
  `{"content":[{"type":"text","text":"The first half of"}],"stop_reason":"max_tokens"}`
  gives `true, "The first half of"`. The openai adapter does the same with
  `finish_reason: "length"`.
  - Reachability: the anthropic adapter sends `max_tokens` 1024 (the default),
    while `max_chars` allows 2000 characters. Derivation, not measured: English
    output runs near one token per Chinese source character, so a draft beyond
    roughly 1,000-1,400 characters can reach the limit.
  - Consequence: the result phase holds partial English. Enter commits it and
    clears the draft, and the tail of the message is in neither place. §7.6
    lists only `refusal`. §8.1 sends "empty response or model refusal" to the
    error path, which keeps the draft. A cut-off response is neither.
  - This was considered for red, as text loss. It stays yellow for three
    reasons: the backend is cloud and not the default, the trigger length is
    derived rather than measured, and the partial text is displayed before
    Enter commits it. The user may raise it.
  - Fix: `parse` returns nil on `stop_reason == "max_tokens"` (anthropic) and
    on `finish_reason == "length"` (openai). That gives `empty` with the draft
    intact, and Shift+Enter still commits the Chinese. Or open it through
    `/design-review`. Record which.

### 🟢 Suggestions
- **`backend.lua:122`: `--noproxy 127.0.0.1,localhost` also replaces the
  `NO_PROXY` variable for remote hosts.** This is the judgment asked for on
  deviation (b).
  - curl 8.7.1's man page says `--noproxy` overrides `no_proxy` and
    `NO_PROXY`. Measured: with `http_proxy` on closed port 9 and
    `NO_PROXY=foo.test`, a request to `foo.test` (mapped to a local listener
    with `--resolve`) goes direct and gets 200 without the flag. With the flag
    it goes to the proxy and exits 7, which is `conn_refused`.
  - Scenario: a cloud `base_url` whose host the user excluded through
    `NO_PROXY` in launchd's environment (`launchctl setenv`), behind a proxy
    that cannot reach it. Every Enter then shows `✗ 翻译服务未启动`. This is
    narrow, because Squirrel does not see shell variables.
  - The loopback half is right. With `http_proxy` set, `127.0.0.1` and
    `LOCALHOST` both bypass the proxy with the list (200) and reach it without
    the list (exit 7). That covers every form `config.load` accepts as
    loopback. A remote host still honours the proxy variables, as intended.
  - Task 5's form, `--noproxy '*'` for loopback and no flag for remote, keeps
    `NO_PROXY` working for remote hosts too. It needs the loopback verdict
    exported from `config.lua`, as Task 5's notes say. Keeping the list is
    also acceptable; then the comment should say it overrides `NO_PROXY`.
- **`backend.lua:124`: `--connect-timeout 1` is a plan constant the design does
  not have.** The curl man page counts DNS, TCP and TLS as the connection
  phase, and each Enter starts a fresh curl, so nothing is reused. §8.2 lets
  cloud raise `timeout_ms` to 4000, but the handshake stays capped at 1 s.
  Derivation, not measured: at a 250 ms round trip, DNS, TCP and a two-trip TLS
  1.2 handshake take about 1 s. The user then sees `✗ 翻译超时` after 1 s despite
  configuring 4. Locally the flag buys nothing, because loopback connects or
  refuses at once. Drop it, or tie it to `timeout_s`.
- **The tests pin neither shell quoting nor the openai key header.** These
  mutants pass 78/78:
  - `('%q'):format(h)` for the headers (line 128)
  - `('%q'):format(...)` for the URL (line 125)
  - the `Authorization` line dropped (line 39)

  The hook's `%q` check fires only on a line that also names `popen`, `curl`,
  `cmd`, `security` or `/bin/sh` (`checks.sh:106`), so the line-128 form gets
  past both layers. The code today uses `json.shq` everywhere. Scenario: a
  later edit to a header argument, the one the key travels in, brings double
  quotes back (dimension 5), and the suite stays green. Fix: one round trip.
  Run the built command through `/bin/sh` with `curl` replaced by
  `printf '%s\n'`, using a key that contains `'`, `$(x)` and a backtick, and
  compare argv exactly. Also assert `Authorization: Bearer <key>` for openai.

### Deviations from the plan
Both code blocks of `task-06-backend.md` were extracted and diffed against the
staged files. The five below are the only differences.
- (a) `tests/test_backend.lua:16-18`, where `s_oa` is configured explicitly:
  required. D4 is committed, and `config.lua:11` defaults to libretranslate.
  The plan's test, run unchanged against the staged module, fails at
  `#1 openai success`.
- (b) `--globoff` and `--noproxy`: an improvement. `--globoff` carries more
  weight than the comment at lines 118-120 gives it ("the second layer"):
  - With `allow_remote: true`, `config.load` keeps
    `https://api.anthropic.com{/v1,@evil.example/v1}` with 0 warnings
    (measured).
  - Without `--globoff` curl expands such a URL. Against a local listener it
    made 2 transfers, and 1 with the flag (measured). The second transfer's
    host would be `evil.example`, carrying the `x-api-key` header.
  - So for a remote URL this flag is the only layer.
    `tests/test_backend.lua:108` pins it, which is enough.

  For `--noproxy`, see green 1.
- (c) `trim` on `[ \t\r\n]`: an improvement. The mutant back to `%s` dies at
  #29 under the `en_US.UTF-8` ctype. It returns `Done ` plus the first two
  bytes of U+4E20.
- (d) `decimal2`: an improvement, with one regression (yellow 1, second
  bullet). The `tostring` mutant dies at #30 under the `de_DE.UTF-8` numeric
  locale. Rounding to two decimals is fine for a temperature: 0.29 renders as
  `0.29`, 2 as `2.00`, and `1e-9` as `0.00`.
- (e) The 3 x 8 matrix: an improvement. It covers 48 pairs, and each asserts
  both `ok == false` and the code.

### What was walked
- **Dimensions 1-3.** The diff has no `ctx`, no `commit_text`, no candidate and
  no session code. D1 is open, but it blocks Tasks 7 and 9, not 6. Dimension 1
  reaches this module only through the contract: every failure must return
  `(false, code)` so that Task 9 keeps the draft. The two exceptions are
  yellow 1 (a raise) and yellow 4 (a truncation that counts as success).
- **Dimension 4.** Module level holds `json`, `M`, `trim`, `decimal2` and
  `M.adapters`. None is written after load, and no value would differ per
  input box.
- **Dimension 5.** Every variable argument goes through `json.shq`: the `-w`
  format, the URL, each header and the body. The unquoted parts are constants,
  or `%d.%03d` of an integer (digits and a dot). The body always starts with
  `{` and the URL with `http`, so `-d` can never read either as an option or
  as `@file`.
- **Dimension 7, checked literally.**
  - `timeout_ms` 1500 becomes `--max-time 1.500`. curl's man page requires a
    dot whatever the locale, and `%d.%03d` always writes one.
  - `max_chars` goes through `utf8.len`: 700 CJK characters (2100 bytes) pass
    and 2001 fail. The byte-count mutant dies at #20.
  - `temperature` appears only in the openai body. Mutants that add it to
    libretranslate or anthropic die, and so does one that drops it from openai.
  - anthropic sends `anthropic-version: 2023-06-01`, a top-level `system` and
    `max_tokens`, walks `content[]`, and handles `refusal`. A mutant against
    each one dies.
  - Each of the eight codes has a path: `conn_refused` (exit 7), `timeout`
    (exit 28), `http_error` (any other exit, 400 and above, an empty body, an
    unknown adapter), `bad_json`, `empty`, `too_long`, `auth_error` (401 and
    403), and `rate_limited` (429). The spellings match the keys at
    `state.lua:11-21` exactly, so each one reaches its §8.1 string.
- **Parse robustness.** 14 openai body shapes, 4 anthropic and 3
  libretranslate were tried. Only the six in yellow 1 raise. JSON `null`
  decodes to `json.null`, a table, and gives `empty`.
- **Dimension 6: 36 mutants on a scratch copy, 28 killed.** A sanity mutant
  that always succeeds also died. The 8 survivors:
  - shell quoting and the `Authorization` header (3, green 3)
  - `real_runner`'s exit code and its `-w` split (2, yellow 3)
  - `--connect-timeout` dropped, which is what green 2 suggests
  - `decimal2` without `+ 0.5`, which is harmless: 0.29 renders as `0.28`
  - an unknown adapter raising. That branch is unreachable, because
    `config.load` forces a known backend (`config.lua:118-121`).

  Step 2's red holds: without `backend.lua`, the test stops at line 2 with
  `module 'ime_translate.backend' not found`.
- **Real processes (agent-run, not observed in an input box).**
  - Through `real_runner`, a closed port gives `conn_refused`.
  - A listener that sleeps gives `timeout` at 1.57 s.
  - A real 401 gives `auth_error`, and a 200 succeeds.
  - A body of about 6 KB carries no `Expect: 100-continue`, so long drafts do
    not add curl's 1 s wait for it.
  - `translate --serve` was not started. The author's run against it stands as
    the author's.
- **Dimension 8.** The diff makes no claim about librime. Its claims about curl
  and the C library were measured:
  - glob expansion, `--noproxy` and the `-w` split: this round
  - the triple from `f:close()`: with `exit 7`, `exit 28` and a signal 9, this
    round
  - `isspace` matching 0xA0, and `LC_NUMERIC`: through the killed mutants in
    (c) and (d)
- **Dimension 9.** `prewarm` is `return nil`. There is no pre-translation and
  no retry.
- **Commands.**
  - `lua tests/test_backend.lua` gives `test_backend: 78 assertions OK`.
  - `scripts/run_tests.sh` exits 0: backend 78, config 75, decide 60, decode
    88, encode 10, state 17.
  - `.githooks/pre-commit` over the staged content exits 0, and `git status` is
    unchanged afterwards.

### Notes outside this diff
- §7.2's "menu bar and log mark it cloud" still has no implementing plan.
  Agreed.
- Spike S13 measured a stall ceiling of 2.5-3 s. Past it, TextEdit loses the
  draft and WeChat duplicates it. Yet `config.load` accepts `timeout_ms` up to
  10000, and §8.2 suggests 4000 for cloud. That belongs to `/design-review`,
  not to a Task 6 fix. Agreed. Green 2 touches the same budget from the other
  side.
- R14, the key and the text in curl's argv, is accepted for v1 in risks.md.
  Agreed. Acceptance 6 concerns logs and error strings, and it holds.
- `config.load` bounds neither `temperature` nor `max_tokens` (Task 5). That is
  where yellow 1's second trigger comes from, and a bound there would also
  close it.
- Task 9's plan calls `translate` without `pcall` (line 147). If yellow 1 is
  fixed here, Task 9 needs no change for it.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_backend.lua` passes every assertion | ok | `test_backend: 78 assertions OK`; `scripts/run_tests.sh` and `.githooks/pre-commit` exit 0 |
| Three adapters x eight error codes fully covered | ok | Lines 131-143 cover 48 pairs, and each checks `ok` and the code. Lines 73-84 add 403, exit 6, an empty body, whitespace-only content and no choices for openai. The transport codes are pinned only through fake runners (yellow 3) |
| temperature carried only by the openai adapter (§7.7) | ok | Line 28 checks presence; lines 46 and 65 check absence. All three mutants die |
| anthropic sends anthropic-version, a top-level system field, and a required max_tokens | ok | Lines 62-64. All three mutants die |
| anthropic walks content[] for type=='text', never content[0] | ok | Line 59. The `content[1]` mutant dies at #5 |
| The api key never appears in any log or error string | ok | Codes are literals, `real_runner` discards stderr, and the module logs nothing. The leak mutant dies at #11. argv visibility is R14 |
| prewarm is an empty function | ok | Line 154. The mutant that calls the runner dies at #22 |

### Verdict
0 red / 4 yellow: no red, clear to close. Fix each yellow, or defer it with a
one-line reason recorded here.

### Author's response (Task 6, round 1)

- **Yellow 1: fixed, in two layers.**
  - The openai `parse` now type-checks each level, as the anthropic adapter
    does. All six bodies give `empty`.
  - `translate` is total. Its body runs under `pcall`, and a raise returns
    `(false, "http_error")`. That is the §7.1 contract, which Task 9 relies on
    without a `pcall` of its own.
  - Temperatures `1e20`, `1e999` and `-1e999` now return `http_error`, and
    nothing is sent. That is the outcome the plan's `tostring` reached through
    the vendor's 400.
  - Tests: the six bodies, and the three temperatures. Each temperature test
    asserts that the runner is never called.
  - Not changed: `config.load` still does not bound `temperature` or
    `max_tokens`. With the wrapper, those values are no longer a crash path, and
    bounding them is a Task 5 change outside this diff.
- **Yellow 2: fixed.**
  - `curl -q` is the first argument. The test asserts the `curl -q ` prefix for
    every adapter.
  - Measured through `real_runner`, with `CURL_HOME` pointing at a `.curlrc`
    that holds `include`, `retry = 2` and `fail`:
    - black hole: `timeout` at 1.53 s, against 1.54 s without the file
    - `translate --serve`: success
  - The trade-off is accepted: a `proxy =` line in `~/.curlrc` is now ignored.
    If cloud through a proxy is ever wanted, it should be an explicit config
    key. That is a question for `/design-review`, and it is not opened now.
- **Yellow 3: fixed.** `real_runner` is tested with shell commands standing in
  for curl:
  - the body and status split
  - a multi-line body
  - no status line
  - `exit 28` and `exit 7`
  - a signal

  Both of the review's mutants die.
- **Yellow 4: fixed as suggested.**
  - anthropic's `stop_reason == "max_tokens"` and openai's
    `finish_reason == "length"` both give `empty`. The user sees
    `✗ 翻译失败`, the draft is kept, and Shift+Enter still commits the Chinese.
  - openai's `finish_reason: "stop"` is pinned as a success.
  - A separate message would need a new code and a new §8.1 row. That was not
    done: §8.1's string for an empty response fits a cut-off one too.
- **Green 1: took Task 5's form.**
  - `config.is_loopback` is exported. It is one line in `config.lua` with no
    change in behaviour, and it is also the verdict §7.2's cloud marker needs.
  - Loopback gets `--noproxy '*'`. Remote gets no flag, so `NO_PROXY` and the
    proxy variables apply.
  - The test asserts that the flag is present exactly for the loopback
    adapters.
- **Green 2: done.** `--connect-timeout 1` is dropped, so `--max-time` bounds
  the whole request. The test asserts the flag is absent. A black hole still
  times out at `timeout_ms`.
- **Green 3: done.** The built command runs through `/bin/sh` with `curl`
  replaced by `printf '%s\n'`.
  - The key and the text are both ``it's $(echo pwned) `id` "q" \ $HOME``.
  - Three cases:
    - openai
    - anthropic
    - a remote openai URL holding `$(…)` and backticks, which `allow_remote`
      accepts
  - The URL, the body and the key header must each come back byte for byte.
  - `Authorization` is asserted present when there is a key and absent when
    there is none.
- **Mutation check.** 28 mutants on a scratch copy, with the control run first.
  - 26 killed.
  - One survivor is equivalent: `.-` for `.*` in the `-w` split. The `$` anchor
    makes the two patterns match the same way.
  - One mutant did not apply. Its pattern was wrong, and the review killed the
    same mutant.
- **Integration after the fixes.** Agent-run through `real_runner` and real
  curl; nobody watched an input box.
  - Closed port: `false conn_refused` in 0.02 s.
  - Black hole with `timeout_ms` 1500: `false timeout` in 1.54 s.
  - `translate --serve`: `true Got it. I'll read it right away.`
  - With the hostile `.curlrc`, the black hole and `translate --serve` results
    are unchanged.
  - The server was killed by PID with SIGKILL. Nothing is listening on 8989.
- **Deviations from the plan made this round**, in addition to (a)-(e):
  - (f) `-q`
  - (g) `--noproxy '*'` for loopback only, and the `config.is_loopback` export
  - (h) no `--connect-timeout`
  - (i) the `pcall` wrapper and the openai type checks
  - (j) a truncated response gives `empty`

  `test_backend` is at 126 assertions, up from 78. Acceptance is unchanged.
- **Notes outside this diff:** agreed. Task 9's plan needs no `pcall` change,
  because `translate` no longer raises.

---

## Task 7: Session state and draft snapshot — round 1

Range: `3f1969e..HEAD` is empty, because Task 7 is staged, not committed. It
was reviewed as
`git diff --cached -- rime/lua/ime_translate/session.lua tests/test_session.lua`.
For both files `git show :path` equals the working tree. The only other change
is the unstaged `progress.json`, which is ledger state and not reviewed.
Time: 2026-09-21T13:47Z

### 🔴 Must fix
- None.

### 🟡 Should fix
- **`tests/test_session.lua:16`: the fake `get_property` returns `nil` for an
  unset key, but librime returns `""`. So no test exercises the branch that
  handles a fresh Context on the real engine (`session.lua:20`,
  `or p == ""`).**
  - Source reading: librime 1.16.0 `src/rime/context.cc`
    `Context::get_property` returns `string()` when the key is absent, and
    librime-lua (`src/lib/lua_templates.h`, `LuaType<std::string>::pushdata`,
    master) pushes the result with `lua_pushstring`. On the machine, reading
    `ime_translate.phase` in a new session gives `""`, never `nil`. S4 measured
    only the round trip of a key that had been set, so nothing measured backs
    the fake's `nil`.
  - Mutant: `if p == nil then` (with `or p == ""` dropped) passes 32/32. It is
    also the obvious tidy-up: lines 24-26 already use `get_property(K) or ""`,
    so rewriting line 19-21 as `return ctx:get_property(K_PHASE) or state.IDLE`
    would pass every test.
  - Consequence, derived from the plan code and not measured: Task 9 passes
    `session.phase(ctx)` straight to `decide` (task-09-glue.md line 165), so a
    new input session would read phase `""`. `decide.lua:46`
    (`code == M.ESC and phase ~= state.IDLE`) treats `""` as not idle. If Esc
    is the first key in a new application or input box, it becomes
    `clear_display`, the processor returns `kAccepted`, and the application
    never receives the Esc (closing a dialog, cancelling a search field). Any
    other first key goes through `invalidate_and_pass` to `session.clear`,
    which writes `idle` and ends the exposure.
  - Fix: make the fake behave like the engine:
    `get_property = function(self, k) return props[k] or "" end`. Checked on a
    scratch copy: the staged module still passes 32/32, and the mutant now
    fails at #1 with `fresh ctx is idle: got "" want "idle"`. Optionally, the
    fake's `set_property` could also refuse a non-string value, as librime-lua's
    `luaL_checkstring` does, so that a future `nil` write fails in the test
    instead of on the machine. Either change departs from the plan's test
    block, so record it as a deviation.

### 🟢 Suggestions
- **`tests/test_session.lua:36` and `:59`: assertions #10
  (`code cleared on result`) and #23 (`text cleared on error`) cannot catch the
  write they are named after.** Each runs from a state where that property is
  already empty: a fresh context in one case, just after `clear` in the other.
  Each of these deletions still passes 32/32: `session.lua:31` (`set_result`
  resetting `K_CODE`), `:37` (`set_error` resetting `K_TEXT`) and `:45`
  (`clear` resetting `K_CODE`).
  - No product path depends on those writes today. Under Task 8's `decide` and
    Task 9's processor, `set_result` and `set_error` are reached only from a
    phase that is neither result nor error. Every exit from `result` or `error`
    runs `session.clear`: both commits, `clear_display`, `invalidate_and_pass`
    (which also catches Control+Enter), and the stale check. And `prompt`
    never reads `code` in `result` or `text` in `error`, and neither do the
    commits.
  - So the writes are defensive, and the test claims more than it checks.
    Either pin them with one direct `set_error` -> `set_result` transition (and
    the reverse), or rename the two assertions.

### Deviations from the plan
- None. Both code blocks of `task-07-session.md` (test at lines 43-125,
  module at lines 138-203) were extracted and compared with `cmp` against the
  staged files, and both are byte-identical. The yellow is a defect in the
  plan's test block, so fixing it will be a deviation.

### What was walked
- **Dimensions 1, 2 and 5.** The diff has no `commit_text`, no `ctx:clear()`,
  no candidate, no `io.popen` and no shell string. `session.prompt` only
  returns a string. The prompt is never read by `get_commit_text()` (F9,
  measured in S11), so what it displays cannot change what gets committed. The
  test's `%q` formats assertion messages, not shell arguments.
- **Dimension 3 (D1 closed 2026-09-21).** Reviewed against the rewritten §6.2,
  which has two checks. `session.stale` is the comparison for check 2, which
  Task 9 runs at the top of every event (task-09-glue.md line 157).
  - Idle is never stale (#6, #19). The mutant without the idle guard dies at
    #6.
  - With the draft edited in result or error, `stale` is true (#14, #26). With
    phase result and no snapshot, it is also true (#27, acceptance 3). The
    mutant that treats an empty snapshot as fresh dies at #27.
  - A composition emptied below Lua while the properties survive (S12 focus
    loss, S13 TextEdit, F10): the draft `""` differs from the snapshot, so the
    next key clears the leftover phase. For the same reason, retyping the
    same draft after a dump cannot bring back the old translation. The first
    key of the retype arrives while the composition is empty, and that clears
    it.
  - A draft brought back to the snapshot without any key (mouse only) is not
    stale (#15). That is the design's "the draft is its own version". The
    display side of this is §6.2's stated residual, which Task 10 owns.
- **Dimension 4.** The only upvalues of the ten exported functions are `M`,
  `state` and the four `K_*` strings. A full cycle of `set_result`,
  `set_error`, `clear`, `prompt`, `stale` and `phase` was run under a strict
  `_G` that raises on any global write. It wrote no global and left the module
  table unchanged, and the only writes were to the four §6.1 keys on the
  context. `state` is stateless (Task 4). The header comment's premise, as a
  source reading: librime-lua `src/modules.cc` (master) creates one
  `an<Lua>` and passes it to all four component registrations.
- **Dimension 6: 16 mutants on a scratch copy, plus an identity control that
  passed. 12 were killed.**
  - Killed:
    - the `nil` check in `phase` removed (#1)
    - `clear` without its text, draft or phase reset (#17, #18, #16)
    - the idle guard removed (#6)
    - an empty snapshot treated as fresh (#27)
    - `draft` without `or ""` (#32)
    - the result prefix changed to `" -> "` (#13)
    - the error prefix dropped (#25)
    - the error prompt reading `text` instead of `code` (#25)
    - `set_result` or `set_error` not writing the snapshot (#11, #24)
  - Survivors: the yellow (1) and the green (3).
  - Step 2's red, re-run with `session.lua` absent from a scratch tree: the
    test stops at line 2 with `module 'ime_translate.session' not found`.
- **Dimension 7.** The keys match §6.1's table literally
  (`ime_translate.phase`, `.text`, `.code`, `.draft`), and the phase values
  are `state.IDLE`, `RESULT` and `ERROR`. `prompt` matches §6.4's table:
  - result: `"  -> "` plus the translation. Byte-checked: two ASCII spaces,
    `->`, then a space. That is the prefix of the S11 probe
    (task-01-spike.md line 336), which produced the measured
    `今天有點累  -> FAKE ENGLISH`.
  - error: two spaces plus `state.error_message(code)`. An unknown or empty
    code falls back to `✗ 翻译失败` (Task 4).
  - idle: `""`.

  The test pins both non-empty strings exactly.
- **Dimension 8.** The engine claims in the diff, and their anchors:
  - `session.lua:13-15` (fluid_editor does not auto-commit, and
    `get_commit_text()` is the whole draft): F1 and F5, measured in S1 and in
    S11 state B (`draft=[今天有點累不過]`). The comment leaves out F5's
    "highlighted candidate of an open segment". §6.1 states it, so this is
    not raised.
  - `:49-51` (the display stays out of `get_commit_text()`): F9, measured in
    S11, and cited through §6.1 and D1.
  - `:57-58` (`"  -> "` is S11's form): the S11 prompt rows of the spike
    report.
  - The fake's `get_commit_text` stands in for F5, which S11 measured. The
    fake's `get_property` is the yellow.
  - Beyond the diff, as a source reading: every `set_property` fires librime's
    `property_update_notifier`. `ConcreteEngine::OnPropertyUpdate` (1.16.0
    `engine.cc`) logs the property name at INFO and sends `name=value` to the
    frontend as a `property` notification. Squirrel 1.1.2's
    `notificationHandler` handles only `deploy`, `schema` and `option`. So
    nothing is displayed, and neither the draft nor the translation reaches a
    log. No finding.
- **Dimension 9.** The ten exports are exactly the plan's interface.
  `snapshot` is used by `stale` and by the tests. Nothing here is something v1
  excludes.
- **Commands.**
  - `lua tests/test_session.lua` gives `test_session: 32 assertions OK`.
  - `scripts/run_tests.sh` exits 0: backend 126, config 75, decide 60, decode
    88, encode 10, session 32, state 17.
  - `.githooks/pre-commit` over the staged content exits 0 (gate, Lua
    invariants, secrets, language, then the suite).
  - Afterwards `git status --short` is unchanged, and so are the hashes of
    `git diff --cached` and `git diff`.

### Notes outside this diff
- The yellow's engine fact (an unset property reads as `""`) has no F-row in
  `upstream.md` §15.2. Adding one is `/design-review`'s call.
- `session.prompt` puts the translation into the preedit unchanged. The
  backend's `trim` strips only the ends, so an LLM answer with inner newlines
  (from a multi-paragraph draft) reaches the prompt, and then `commit_text`,
  with its `\n` intact. How Squirrel's marked text and each application render
  or commit that is **unverified**. §6.4 already gives long prompts to Task
  10's smoke checks, and a multi-line translation belongs in the same row.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_session.lua` passes every assertion | ok | `test_session: 32 assertions OK`, exit 0. `scripts/run_tests.sh` and `.githooks/pre-commit` exit 0 |
| All state goes through Context properties; no session state left at module level | ok | The upvalues are `M`, `state` and four key strings. The strict-`_G` run writes no global and leaves the module table unchanged. The only writes go to the context, under the four §6.1 keys. #28-#30 check two contexts |
| `session.stale` judges correctly for both draft-differs and snapshot-missing | ok | #14 and #26 (draft differs, in result and in error), #27 (snapshot missing). A mutant against each one dies. A missing snapshot is `nil` in the fake and `""` in the engine, and `snapshot()` maps both to `""`, so this verdict holds on the machine. The phase getter does not share that luck (yellow) |

### Verdict
0 red / 1 yellow: no red, clear to close. Fix the yellow or defer it with a
one-line reason recorded here. The green is advisory.

### Author's response (Task 7, round 1)

- **Yellow 1: fixed as suggested.**
  - The fake's `get_property` now returns `props[k] or ""`, as the engine
    does. #1 `fresh ctx is idle` therefore goes through the `p == ""` branch.
  - Added a store that returns `nil`, which is the shape spike S4's fallback
    would have, to keep the other half of that branch pinned.
  - Both mutants of `session.lua:20` die: `""` no longer counted as idle, and
    `nil` no longer counted as idle.
- **Green: done.** Three assertions, each run after the field it names has been
  set:
  - `set_result` after `set_error` clears the code
  - `set_error` after `set_result` clears the translation
  - `clear` after an error clears the code

  The review's three survivors, deleting lines 31, 37 and 45, now die.
- **Mutation check.** 11 mutants on a scratch copy, all killed, with the
  unmutated control run first and passing. They are:
  - the review's four survivors
  - `clear` keeping the text and keeping the snapshot
  - `stale` ignoring idle
  - both prompt forms
  - `draft` passing `nil` through
- **Deviations from the plan:** `tests/test_session.lua` only. The fake's
  default changed and four assertions were added; `test_session` is at 36
  assertions, up from 32. `session.lua` is still byte-identical to the plan.
  Acceptance is unchanged.
- **Notes outside this diff: agreed.**
  - The unset-property fact is not an F-row, and that is left for a
    `/design-review`.
  - A translation containing newlines is now on Task 10's revision list, next
    to the long-prompt smoke checks.

---

## Task 9: Rime glue layer — round 1

Range: `6e7b262..HEAD` is empty, because Task 9 is staged, not committed. It
was reviewed as
`git diff --cached -- rime/lua/ime_translate_shared.lua rime/lua/ime_translate_processor.lua tests/test_glue_load.lua tests/test_processor.lua`.
For all four files `git show :path` hashes the same as the working tree. The
only other change is the unstaged `progress.json`, which is ledger state
(Task 7 closed, Task 9 started) and not reviewed.
Time: 2026-09-21T14:26Z

Nothing here has run inside Squirrel. Every engine claim below is labelled a
source reading, a derivation, or measured in the spike.

### 🔴 Must fix
- **`rime/lua/ime_translate_processor.lua:74-76` and `:67-69`: when the caret
  sits inside unconverted input, the processor commits only the text before
  the caret, and then `ctx:clear()` destroys the rest of the input.** The same
  cause makes `:54` translate only that prefix. This is a derivation from a
  source reading and has not been measured.
  - **Source reading** (librime 1.16.0 at tag `1.16.0`; master is the same):
    - `engine.cc` `ConcreteEngine::Compose` resets the composition to
      `input().substr(0, caret_pos())`. It uses the full input only when the
      caret is exactly at the confirmed position.
    - `segmentation.cc` `Segmentation::Reset` stores that string as the
      composition's `input_`.
    - `composition.cc` `Composition::GetCommitText` appends only
      `input_.substr(end)`. `GetPreedit` also appends
      `full_input.substr(end)`. So the text after the caret is on screen but
      is not in `get_commit_text()`.
    - `gear/navigator.cc` binds Left to `Navigator::Rewind`, which moves the
      caret one stop left with `set_caret_pos`, into unconverted input.
  - **Scenario.**
    1. Type `jintiantianqihenhao` without selecting anything, so the
       confirmed position is 0.
    2. Press Left once. The caret moves into the pinyin, before `hao`.
       `decide` gives `noop` in `idle`, so the native navigator handles the
       key.
    3. Press Shift+Enter. `decide` gives `commit_draft`. Line 74 commits the
       highlighted conversion of `jintiantianqihen`, and line 76 clears the
       whole input.

    `hao` is neither committed nor kept: the user loses the last word of a
    sentence they had already typed. The same happens with Enter then Enter
    (the prompt shows the prefix's translation, and the second Enter commits
    it), and with Enter in the error phase (it commits the prefix in
    Chinese).
  - **Native Return does not lose the tail.** `Editor::CommitComposition`
    calls `ConfirmCurrentSelection`. That reaches `ConcreteEngine::OnSelect`,
    which moves the caret to the end and does not commit.
  - **Headless model** (a fake, so an illustration only): `get_commit_text`
    returns the prefix before the caret, and `input` holds the full string.
    Shift+Enter commits the prefix and leaves `input` as `""`. The processor
    never reads `ctx.caret_pos` or `ctx.input`.
  - **Why this is red although the acceptance item passes.** The item "every
    `ctx:clear()` is preceded by a `commit_text`" holds as written. But what
    gets committed is `get_commit_text()`, and what `ctx:clear()` removes is
    the whole input, so §6.3's "The draft never vanishes" fails. The anchors
    this path rests on are incomplete:
    - `upstream.md` §15.2 F5 says "+ any unconverted input" and leaves out the
      truncation at the caret.
    - `session.lua:13-15` repeats "the whole Chinese draft".
    - §6.4 lists "the caret not at the end" as unmeasured, but only for where
      the prompt lands.
  - **The fix is a behaviour choice, so it is the user's call.** Two options:
    - On `translate` and on both commits, first move the caret to the end
      when `ctx.caret_pos < #ctx.input`, then re-read the draft. librime-lua
      makes `caret_pos` settable (`types.cc` `ContextReg`). The recompose can
      re-segment the part before the caret, so what the user saw may change.
    - Refuse the key while the caret is not at the end.

    Passing Shift+Enter to the native chain is not a fix:
    `Editor::CommitScriptText` reads `GetScriptText`, which is truncated the
    same way, and then calls `Clear()`. Whichever option is chosen needs a
    headless test (a fake whose draft stops at the caret) and a Task 10 smoke
    row that measures what Shift+Enter and Enter-Enter commit with the caret
    moved left. Alternatively, the user accepts the risk explicitly, and that
    is recorded here.

### 🟡 Should fix
- **`rime/lua/ime_translate_processor.lua:42-50`: Esc pressed right after a
  change to the draft that came with no key event wipes the whole draft.**
  Check 2 runs first and puts the phase back to `idle`. `decide` then sees
  Esc in `idle` and returns `noop`. The key goes on to the native
  `CancelComposition`, which spike S11 row 5b measured wiping the whole draft
  with nothing committed.
  - **Trigger, from source.** In state B (last segment open, Rime's candidate
    window visible, the prompt showing), the user scrolls the candidate panel
    or clicks its page arrow. The call chain:
    1. `SquirrelPanel.swift` `.scrollWheel` / `.leftMouseUp`
    2. `SquirrelInputController.page(up:)`
    3. `rime_api.change_page`
    4. `RimeChangePage` (`rime_api_impl.h`)
    5. `Context::Highlight`, which changes `selected_index`

    So by F5 the draft changes with no key event. `TranslateSegments` skips
    segments already at `kGuess`, so the last segment and its prompt survive
    the recompose. This is a derivation: the old translation stays on screen,
    which is §6.2's stated residual.
  - **What the user does.** They press Esc, which §5.2 says discards the
    translation and keeps the draft, and they lose the draft instead. Enter in
    the same situation is safe (it re-translates). Only Esc is destructive.
  - **Why yellow, not red.** The processor follows §6.2 and §5.2 to the
    letter, and the wipe is the designed native Esc in `idle`. The chain also
    rests on two unmeasured links.
  - **Fix.** Accepting the Esc when check 2 fired in the same event (treating
    it as `clear_display`) changes §5.2, so it needs `/design-review`, or the
    residual is accepted and recorded in §6.2. Either way, it needs a Task 10
    smoke row next to §6.4's "mouse click on a candidate".
- **`tests/test_processor.lua:25-28`: the stub records only `text`, so nothing
  pins what the processor passes to `backend.translate` at line 54.** These
  mutants of line 54 each pass all 46 assertions:
  - runner `nil`
  - api key `nil`
  - settings `{}`

  Checked against the real `backend.translate`:
  - A `nil` runner or `{}` settings gives `http_error`, so every Enter shows
    `✗ 翻译失败`.
  - A `nil` key sends `x-api-key: ` empty. With an anthropic or openai
    backend, the vendor's 401 turns every Enter into `✗ 密钥无效`.

  The file's header says it pins the processor's paths "rather than left to
  the machine". The key mutant is one the machine would not catch either,
  because Task 10's smoke checks run the local backend. Fix: record all four
  arguments in the stub, set `shared.api_key` to a sentinel string, and assert
  `settings == shared.settings`, `runner == backend.real_runner` and
  `key == shared.api_key`.

### 🟢 Suggestions
- **`tests/test_processor.lua:42`: the fake's `composition.back()` always
  returns a segment, so the guard at `ime_translate_processor.lua:23`
  (`if draft ~= ""`) is not pinned.** The fake also cannot contradict the
  claim in the comment at `:20-21`, and that claim has no anchor. Anchors, as
  source readings:
  - librime-lua `types.cc` `CompositionReg::back` returns `nullptr` on an
    empty composition, which is `nil` in Lua.
  - `lua_gears.cc` `LuaProcessor::ProcessKeyEvent` logs a raise and returns
    `kNoop`.

  The guard matters after a focus loss (S12). The composition is emptied
  below Lua, the properties survive, and the next key goes through check 2
  with a draft of `""`. Checked on a scratch copy: make the fake return `nil`
  when `_text == ""`, and add that sequence (translate, empty the draft,
  press a letter). The staged processor passes 46 + 1. The mutant without the
  guard fails with `attempt to index a nil value`. Citing the two anchors in
  the comment would close dimension 8 for it.
- **`rime/lua/ime_translate_shared.lua:27-40`: no test calls
  `shared.ensure()`.** `test_processor.lua:19-20` fills `shared` in by hand,
  so a wrong config path or a wrong `security` argv would pass every test.
  - I ran it once in a sandbox: `HOME` pointed at a scratch directory with an
    `ime_translate.yaml`, and `PATH` started with a fake `security` that
    records its argv. Results:
    - the settings loaded
    - `typo_key` came back as a warning
    - the key was trimmed of its newline
    - a second call returned the same table
    - an account of `a'b$(touch …)` arrived as a single argv entry, and
      nothing ran
  - The same check fits in a test by replacing `os.getenv`, `io.open` and
    `io.popen` before calling `ensure()`.

### Deviations from the plan
- `ime_translate_shared.lua`, `ime_translate_processor.lua` and
  `tests/test_glue_load.lua` are byte-identical to the three code blocks of
  `task-09-glue.md`. I extracted the blocks and compared them with `cmp`.
- `tests/test_processor.lua` was added. The deviation is explained in the
  file's header (lines 2-4) and in the author's brief. It is an improvement:
  the plan's only test is a load smoke test, and this file drives every
  action. Its fake `ctx:clear()` asserts §6.3 on each call. Not an
  unexplained deviation.

### What was walked
- **Dimension 1.** The only `commit_text` calls in `rime/` are processor lines
  67 and 74. The only `ctx:clear()` calls are 69 and 76, each two lines after
  a commit. `session.text` and `draft` never return `nil`.
  - In `result`, `text` is non-empty. Task 6 trims and refuses an empty
    translation, and `set_result` is the only writer.
  - Raises: `backend.translate` is total (Task 6). A raise anywhere else in
    the processor becomes `kNoop` (`lua_gears.cc`, above). Before a commit,
    that sends the key to the native chain, which does not eat text: Return
    confirms or commits the Chinese.
  - Between `ctx:clear()` and `return kAccepted` there is only `log()`. It
    could raise only with `HOME` unset, and the spike probe's
    `os.getenv("HOME")` log worked inside Squirrel. If it did raise, Enter
    would reach the application.
  - The caret case is the red.
- **Dimension 2.** No translator, no filter, no candidate, and no
  `ctx:commit()`. The prompt is never read by `get_commit_text()` (F9,
  measured in S11), so the display cannot change what is committed.
  `test_glue_load` refuses both removed modules. I checked that it goes red
  with a stub `ime_translate_filter.lua` present.
- **Dimension 3 (D1 closed: two checks).**
  - Check 1 is `decide.lua:54` (Task 8).
  - Check 2 is `processor.lua:42-45`. It runs before `decide` on every event,
    releases included, and clears the prompt as well as the phase.
  - Killed mutants: check 2 disabled, check 2 moved after `decide`, and
    `decide` fed the phase from before check 2. All three die at #33
    (`the stale translation is not committed`). The author's "check 2 keeps
    prompt" is killed too.
  - After the paging trigger above, Enter re-translates. Only Esc is exposed
    (yellow 1).
- **Dimension 4.**
  - The processor's module-level names are the four required modules,
    `kAccepted`/`kNoop`, `log` and `show`.
  - `shared` holds `settings`, `warnings`, `api_key` and `loaded`. All four
    are process-wide. `warnings` is replaced once, so the log gets it once
    per process.
  - I ran two fake sessions interleaved under a `_G` that raises on any
    global write. No global was written. The only change to `shared` was
    `warnings`. One session's `result` did not reach the other, and each
    committed only its own text.
- **Dimension 5.** `shared.lua:17-18` builds the command with `json.shq`.
  The sandbox run above showed the hostile account going through inert. The
  `%q` at `processor.lua:60` formats a log line, not a shell argument.
- **Dimension 6.**
  - Step 2 red, re-run in a scratch tree:
    `fail to load ime_translate_shared: module 'ime_translate_shared' not found`.
    With only `shared` present it fails on `ime_translate_processor`.
  - 19 mutants of my own, separate from the author's 18. The unmutated
    control passed first.
  - 14 were killed:
    - `commit_draft` committing the snapshot
    - an empty snapshot on result, and on error
    - the final return changed to `kAccepted`
    - `draft_empty` inverted
    - Esc keeping the phase
    - the three check-2 mutants
    - translating the snapshot
    - committing the prompt
    - `kAccepted`/`kNoop` swapped
    - release ignored
    - modifier dropped
  - 5 survived:
    - the three wiring mutants (yellow 2)
    - the guard (green 1)
    - `S.warnings = {}` removed, which is harmless: it only repeats warnings
      in a debug log
- **Dimension 7.**
  - `kAccepted, kNoop = 1, 2` and `key:release()` match the spike report's
    "Constants later tasks need".
  - The `security find-generic-password -s ime-translate -a <account> -w`
    command matches §7.3.
  - The config path `~/Library/Rime/ime_translate.yaml` and the log under
    `~/Library/Logs/` match §9.
  - The prompt forms come from `session.prompt` (Task 7). The error strings
    come from `state` (Task 4), and every code comes from Task 6.
- **Dimension 8.** Engine claims in comments, and their anchors:
  - `:10`: the spike constants.
  - `:19-20`: F9 and S11.
  - `:20-21`: no anchor (green 1).
  - `:38-41` (mouse click): §6.2.
  - `:47-48`: R15, Task 8 and the spike constants.
  - `:57-58`: F8, §6.4 and S11.
  - `:64-66`: F10, the spike's "properties survive `ctx:clear()`".
  - `:81-82`: S11 row 5b.
  - The one-Lua-state claim in `shared.lua:1-3`: §6.1, and librime-lua
    `modules.cc` (source reading, Task 7 round).

  The fake's `get_commit_text` stands in for F5, and F5 is where the red's
  gap is.
- **Dimension 9.** No `prewarm` call (§8.3), no translator or filter (D1),
  and no async path. The one deviation is explained.
- **Commands.**
  - `lua tests/test_glue_load.lua` gives
    `test_glue_load: 2 modules OK, shared is lazy and stateless`.
  - `lua tests/test_processor.lua` gives `test_processor: 46 assertions OK`.
  - `scripts/run_tests.sh` exits 0: backend 126, config 75, decide 60,
    glue_load ok, decode 88, encode 10, processor 46, session 36, state 17.
  - `.githooks/pre-commit` exits 0.
  - Afterwards, `git status --short` is unchanged, and so are the hashes of
    `git diff --cached` and `git diff`.

### Notes outside this diff
- F5 in `upstream.md` §15.2, and the comment at `session.lua:13-15`, should
  say that `get_commit_text()` stops at the caret unless the caret is at the
  confirmed position. Amending the F-row is `/design-review`'s call.
- §6.4's Task 10 list should include what gets committed with the caret moved
  left, not only where the prompt lands.
- The spike report's `rime.lua` binding trap ("Tasks 9 and 10 inherit") is
  about wiring. It belongs to Task 10, not to this diff.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_glue_load.lua` passes (both modules load with the right export shape) | ok | Passes. It goes red with either module missing, and with a removed component present |
| `engine:commit_text` appears only in `ime_translate_processor.lua` | ok | grep over `rime/`: lines 67 and 74 only. No candidate path, no `ctx:commit()` |
| `shared` has no fsm / phase | ok | Asserted in `test_glue_load`. The strict-`_G` run shows `shared` gains no session field |
| Both invalidation checks are present: `decide`, and the top of every processor event, which also clears the prompt | ok | `decide.lua:54`; `processor.lua:42-45`, before `decide`. Its three mutants and the prompt mutant die |
| Every `ctx:clear()` is preceded by a `commit_text` (never eat text) | ok as written, **fails in substance** | 67→69 and 74→76 hold literally. With the caret inside unconverted input, the commit covers only the text before the caret, and `ctx:clear()` removes the rest (red) |

### Verdict
1 red / 2 yellow: the task **cannot** be marked done. The red needs a fix,
or the user's explicit acceptance recorded here. Its fix is a behaviour choice
(§6.3, §6.4), so the user makes it.

### Author's response (Task 9, round 1)

- **Red: fixed. The user chose "move the caret to the end, and stop there"**
  (decisions.md, "Task 9 review: the caret …").
  - When `decide` returns `translate`, `commit_translation` or `commit_draft`
    and `ctx.caret_pos < #ctx.input`, the processor does three things and
    returns `kAccepted`:
    - clears the phase and the prompt
    - sets `ctx.caret_pos = #ctx.input`
    - commits, clears and translates nothing

    The next press acts on the whole draft, which is now on screen.
  - `decide` now gets "empty" as `ctx.input == ""`. With the caret at the
    start, a Shift+Enter therefore goes through the same guard and is not
    passed to the native `CommitScriptText`.
  - Tests use a fake whose commit text stops at the caret:
    - Shift+Enter with the caret inside commits nothing, keeps the input whole
      and moves the caret. The second Shift+Enter commits the whole draft.
    - Enter with the caret inside does not translate the part before the caret.
    - Shift+Enter with the caret at the start keeps the pinyin.
  - Design: §5.2 (the rule, and what "non-empty" means), §6.3 (the whole draft)
    and a new F15 row with this review's source reading.
  - `session.lua`'s comment now says "with the caret at the end". That is a
    comment-only change to a Task 7 file.
  - **Not measured.** Two things are unverified: that assigning `caret_pos`
    from Lua recomposes the way the native Return's `OnSelect` does, and what
    the recompose does to the part before the caret. Task 10's revision note
    now carries the smoke row: Left, then Shift+Enter, and Enter then Enter.
- **Yellow 1: fixed. The user chose to take the Esc**, in the same decision.
  - If check 2 fires, a draft is left, and the key is an Esc press, the
    processor returns `kAccepted` after clearing the phase and the prompt.
  - With no draft left (a composition emptied below Lua), the Esc goes on to
    the application.
  - Tests:
    - After a no-key edit, Esc keeps the draft and drops the prompt.
    - The next Esc is plain idle.
    - An Esc with no draft left passes on.
  - Design: §5.2 and §6.2's residual.
  - Smoke row in Task 10's note: page the candidate window with the wheel, then
    Esc.
- **Yellow 2: fixed.** The stub records all four arguments, and
  `shared.api_key` is the sentinel `k-sentinel`. The tests assert the settings,
  `backend.real_runner` and the key. The runner-`nil`, key-`nil` and
  settings-`{}` mutants all die.
- **Green 1: done.** The fake's `back()` returns `nil` for an empty
  composition. A key pressed after the composition has vanished below Lua
  passes on without an error. The mutant that removes the guard dies.
- **Green 2: deferred.**
  - `shared.ensure()` reads `$HOME` and runs `security`. A headless test would
    have to spawn a child with a different `HOME` and `PATH`.
  - This review already ran it in such a sandbox. Task 10 runs it for real,
    with the installed config and the Keychain.
- **Mutation check.** 29 mutants on a scratch copy, with the control run first.
  All 29 are killed:
  - round 1's 18
  - the caret guard: off, no caret move, only on `translate`, skipping
    `commit_draft`, and "empty" read from the commit text
  - the stale Esc: passed on, and taken with no draft
  - this review's three wiring mutants
  - the `show` guard
- **Deviations from the plan:**
  - `ime_translate_processor.lua` gains the caret guard, the stale-Esc rule and
    the input-based "empty". All three follow the user's decisions above.
  - `tests/test_processor.lua` is at 68 assertions, up from 46.
  - `session.lua`: the comment above.
  - `ime_translate_shared.lua` and `tests/test_glue_load.lua` are still
    byte-identical to the plan.
  - Acceptance is unchanged.

---

## Task 9: Rime glue layer — round 2

Range: `6e7b262..HEAD` is still empty, because Task 9 is staged, not committed.
It was reviewed as
`git diff --cached -- rime/lua/ime_translate_shared.lua rime/lua/ime_translate_processor.lua rime/lua/ime_translate/session.lua tests/test_glue_load.lua tests/test_processor.lua`
(index and working tree hash the same for all five files), plus the unstaged
design edits
`git diff -- docs/design/architecture.md docs/design/decisions.md docs/design/upstream.md docs/features/001-zh-en-ime/plan/task-10-wiring.md`.
`progress.json` is ledger state and was not reviewed.
Time: 2026-09-21T15:01Z

Nothing here has run inside Squirrel. Upstream read this round: librime at tag
`1.16.0` (release tarball), librime-lua master `src/types.cc`, and Squirrel
master `SquirrelInputController.swift`, `SquirrelPanel.swift` and
`SquirrelView.swift`. Every engine claim below is labelled.

### 🔴 Must fix
- None. Round 1's red is closed on every path I could enumerate (see "What was
  walked"). That rests on source reading and derivation, not on measurement.

### 🟡 Should fix
- **`rime/lua/ime_translate_processor.lua:51` with `:89-97`: clicking the
  highlighted candidate while the translation shows removes the prompt but
  keeps the phase, so the next Enter commits English that is no longer on
  screen.** This was not introduced by this round; round 1 missed it. It is a
  derivation from source reading and has not been measured.
  - Chain (librime 1.16.0 unless noted):
    1. State B (S11): the last segment is open, Rime's candidate window is
       showing, and the prompt `  -> …` sits on that segment. Candidate 0 is
       typically the whole-sentence candidate, and it is highlighted.
    2. The user clicks it. Squirrel master `SquirrelPanel.sendEvent`
       `.leftMouseUp` → `selectCandidate` → `RimeSelectCandidateOnCurrentPage`
       → `Context::Select`, which sets `kSelected` and fires
       `select_notifier`. There is no key event.
    3. `ConcreteEngine::OnSelect`: the segment ends at the end of the input,
       so it becomes `kConfirmed`. `fluid_editor` constructs `Editor` with
       `_auto_commit` false, so `Forward()` pushes a new, empty last segment.
    4. `Composition::GetPrompt` reads only `back().prompt`, which is the new
       segment's `""`. The English disappears from the preedit.
    5. `GetCommitText` is unchanged: the same candidate text, and the empty
       segment adds nothing. `session.stale` stays false and the phase stays
       `result`.
    6. Enter: check 2 passes, `decide` gives `commit_translation`, the caret is
       at the end, and line 93 commits the English.
  - What the user sees: the Chinese alone, with no translation, and then
    English lands in the box on the first Enter. By §5.2, an Enter with no
    translation on screen translates; this one commits. It stays yellow, not
    red, for three reasons:
    - the English is the right translation of the current draft
    - it was on screen until the click
    - sending is manual

    Still, it is the one path where what commits is not what is on screen at
    that moment.
  - Headless illustration (a fake, not evidence): a fake whose `Forward()`
    pushes a new empty last segment shows prompt `""` after the click, and the
    next Enter commits `EN(今天天气很好)`.
  - §6.2's residual covers only the opposite case, where the prompt outlives
    the edit. §6.4 already sends "a mouse click on a candidate while the prompt
    shows" to Task 10, but with no expected outcome.
  - The fix is a behaviour choice, so it is the user's. Options:
    - (a) Extend check 2 to the display: in `result` or `error`, a last
      segment whose `prompt` is not `session.prompt(ctx)` counts as stale.
      That changes §6.2, so it goes through `/design-review`.
    - (b) `commit_translation` commits only while the prompt is on `back()`.
      Otherwise it shows the prompt again and takes the key.
    - (c) Defer to Task 10, and write the expected outcome into the smoke row.
- **An upstream claim contradicted by the source it cites (dimension 8): "with
  the caret at the start the commit text is empty".** It appears in four
  places:
  - `rime/lua/ime_translate_processor.lua:66-68`
  - `tests/test_processor.lua:207-212`, whose fake returns `""` at caret 0
  - architecture.md §5.2, the caret paragraph
  - decisions.md, the rationale for the input-based "empty"

  Source reading, librime 1.16.0 `engine.cc` `ConcreteEngine::Compose`:
  - After `comp.Reset(input.substr(0, caret))`, if the caret is before the end
    of the input and equals `comp.GetConfirmedPosition()`, it calls
    `comp.Reset(ctx->input())`, the full input. `CalculateSegmentation` then
    translates one segment past the caret, and `Composition::GetCommitText`
    appends the raw rest of the input.
  - At caret 0, `Reset("")` has disposed every segment, so
    `GetConfirmedPosition()` is 0 and the branch always fires. Two keys put the
    caret there: Home, or Left pressed until `Navigator::JumpLeft` stops at the
    confirmed position. `get_commit_text()` is then the whole draft, not `""`.
  - Round 1's red recorded this exception: "It uses the full input only when
    the caret is exactly at the confirmed position." upstream.md F15 dropped
    it. F15 now says the composition "is built from
    `input().substr(0, caret_pos())`, so `GetCommitText` stops at the caret",
    which is the same shape as the F5 gap behind round 1's red.

  Behaviour is not affected:
  - The guard reads `caret_pos < #input`, not the commit text, so Shift+Enter
    at caret 0 is caught either way.
  - `ctx.input == ""` is still a correct "empty".

  What is wrong is the record:
  - The test's fake encodes a state the engine does not produce at caret 0.
    The author's mutant "empty read from the commit text" dies only at #59
    (`shift-enter at the start is not passed to native`), and only because of
    that premise. On the engine it behaves exactly like the staged code.
  - decisions.md's "not passed to the native `CommitScriptText`, which is
    truncated the same way" is also false at caret 0: the script text is not
    truncated there.
  - F15 also leaves out the link line 74 rests on. Source reading:
    - librime-lua master `types.cc` `ContextReg` `vars_set` maps `caret_pos`
      to `Context::set_caret_pos`.
    - At 1.16.0, `Context::set_caret_pos` clamps to the input length and fires
      `update_notifier_`.
    - `ConcreteEngine::OnContextUpdate` then runs `Compose` synchronously. It
      is the same setter that `Navigator::GoToEnd` (End) and `RimeSetCaretPos`
      use.

    I read this chain this round, so the never-eat-text fix does not rest on
    an unverified link. It belongs in F15, so that the next reader does not
    need this log.

  Fix:
  - Add the confirmed-position branch and the setter chain to F15.
  - Correct the §5.2 sentence, the comment at `:66-68`, and the test comment at
    `:207`. The test can stay as a belt-and-braces case if it says the state is
    fake-only; or make the fake return the whole draft at caret 0.
  - Correct decisions.md's rationale.

### 🟢 Suggestions
- **`rime/lua/ime_translate_processor.lua:29-31`, and §5.2's "native Return
  under `fluid_editor` does the same": this holds for the caret only.** It is a
  derivation from source reading (1.16.0).
  - After the Lua assignment, `Compose` resets to the full input.
    `Segmentation::Reset` keeps the open prefix segment, because its end is not
    past the old caret.
  - `CalculateSegmentation` restarts at that segment's start. `AddSegment`
    overwrites it with abc_segmentor's longer segment, a fresh `kVoid` one,
    which is re-translated with `selected_index` 0.
  - Native Return first confirms the highlighted candidate
    (`ConfirmCurrentSelection` → `OnSelect` → `Forward`, then
    `set_caret_pos`).

  Scenario: press Left into the pinyin, press Down to highlight the second
  candidate for the part before the caret, then press Enter. The highlight is
  dropped and the whole run is re-converted. Nothing is committed or translated
  unseen, so no red line is involved. Qualify the comment and §5.2, and add
  "highlight a non-default candidate, then Enter" to Task 10's caret row.
- **`:58` takes more than §5.2's Esc paragraph says.** §5.2 says the Esc is
  taken when check 2 "has just voided a prompt that was still on screen". The
  code takes it whenever check 2 fires on an Esc press and a draft is left.
  When the no-key edit rebuilt the last segment, the prompt is already gone.
  Two ways that happens:
  - a click on a non-default candidate: the `Forward` above, and the draft
    changes
  - with `inline_preedit: false`, a click on the panel's preedit: Squirrel
    master `SquirrelPanel` `.leftMouseUp` → `moveCaret` → `RimeSetCaretPos`,
    whose `Compose` disposes the segment

  That Esc then does nothing visible, and the second one reaches the native
  cancel. Nothing is lost. Say so in §5.2 or in the Task 10 row.
- **My own mutants: 13, with the control run first. 7 killed, 6 survived.**
  - Near-equivalent today:
    - `commit_translation` dropped from `ACTS_ON_DRAFT`
    - `session.clear` dropped from the guard
    - `show` dropped from the guard

    All three differ from the staged code only in `result` or `error`, with
    the caret inside and an unchanged draft. By the Compose reading above,
    that state arises only when a no-key caret move lands on the confirmed
    position. There the composition already spans the whole input, so even
    the first mutant loses nothing. One test would pin the entry that stands
    between that state and a lossy commit, if the rule ever changes: translate,
    move the fake's caret inside and keep `_text`, press Enter, then assert
    nothing committed, the caret at the end, and prompt `""`.
  - The Esc rule with `key.modifier == 0` added. An Esc carrying the Lock bit
    after a no-key edit would then go native. That is unreachable under the
    stock `Caps_Lock: clear` (Task 8 review). `press(env, ESC, 0x2)` pins it.
  - Equivalent: `not key:release()` removed. Squirrel's `recognizedEvents` is
    keyDown and flagsChanged, so no Esc release ever reaches librime.
  - A behaviour alternative, not a bug: a guard keyed on Return ahead of
    `decide`.

### Notes outside this diff
- **Modified Esc (the brief's "modifiers").**
  - Squirrel sends a modifier's own press as a separate event first (master,
    the `.flagsChanged` branch; Task 8 review, observation (b)).
    - In `result`, the Shift press is `invalidate_and_pass` (`decide.lua:54`).
    - After a no-key edit, check 2 fires on the Shift press, which is not Esc.
  - Either way, the Shift+Esc that follows arrives in `idle` and goes native.
    fluid_editor's `KeyBindingProcessor` `IgnoreShift` fallback maps it onto
    `{Escape, 0}` → `CancelComposition` (1.16.0 `key_binding_processor_impl.h`,
    `editor.cc`), and the draft is wiped.
  - So under Squirrel, `decide.lua:44-45`'s modified-Esc branch is unreachable
    for Shift. Observation (b) weighed only Shift+Enter. Control+Esc and
    Alt+Esc get no fallback at 1.16.0, and they reach the application.
  - The new Esc rule matches the result-phase behaviour and its own wording
    ("the same event"), so this is not a finding against this diff. It belongs
    to Task 8 and §5.2.
  - A Task 10 smoke row would measure it: translation showing, then Shift+Esc.
    Headless probe: both sequences return kNoop for the Shift+Esc.

### Deviations from the plan
- `ime_translate_shared.lua` and `tests/test_glue_load.lua` are byte-identical
  to the plan's first two code blocks. I extracted them again and compared with
  `cmp`.
- `ime_translate_processor.lua` differs from the third block in exactly the
  places the author's response lists. Each follows the user's decisions in
  decisions.md:
  - the caret guard, `:26-33` and `:71-76`
  - the stale Esc, `:54-60`
  - the input-based "empty", `:66-69`
- `session.lua` differs by the comment only.
- `tests/test_processor.lua` goes from 46 to 68 assertions.
- No deviation is unexplained.

### What was walked
- **Round 1's red, on every path.**
  - The only `commit_text` calls are at `:93` and `:100`, and the only
    `ctx:clear()` calls at `:95` and `:102`. Both branches are reachable only
    past `:71`, which returns for `translate`, `commit_translation` and
    `commit_draft` whenever `caret_pos < #input`.
  - Every `decide` outcome with the caret inside is stopped by the guard:
    - idle Enter gives `translate`
    - idle Shift+Enter gives `commit_draft`. So does Shift+Enter in `result` or
      `error`, which arrives in idle after the Shift press.
    - Enter in `result` gives `commit_translation`
    - Enter in `error` gives `commit_draft`

    Enter with an empty input goes native, with nothing to lose. With the caret
    at the start, `0 < #input`, so the guard stops it too.
  - With `caret_pos == #input`, `Compose` builds from the full input and
    `GetCommitText` appends any raw remainder, so the committed draft is the
    whole input. Two exceptions, and neither applies:
    - `phony` segments, which only affix_segmentor and chord_composer produce.
      The Task 10 schema lists neither.
    - the `dumb` option, which is set only on the switcher's own context.
  - The guard commits nothing and clears nothing. `set_caret_pos` clamps, so
    the caret ends at `#input` and the guard cannot fire twice on the same
    state. The next press sees the recomposed whole draft, which is on screen,
    and a commit still needs one more press. The fix adds no text-eating path
    and no unseen commit. The one unseen-commit path I found (yellow 1) is
    older than this round.
  - A no-key caret move does exist: Squirrel's panel preedit click (with
    `inline_preedit` off) calls `RimeSetCaretPos`.
    - If the move changes the draft, check 2 voids the phase, and the next
      Enter hits the guard.
    - If it does not (the caret lands on the confirmed position), the
      composition already spans the input.
- **The Esc rule.**
  - Releases: `key:release()` is excluded, and Squirrel never forwards keyUp
    (source reading).
  - Modifiers: an Esc press carrying Lock is taken, because the rule does not
    read the modifier. Shift+Esc, Control+Esc and Alt+Esc never reach the rule
    in the same event as check 2 (see the note above).
  - Empty draft: `draft ~= ""` passes the Esc on when the composition vanished
    below Lua (tested). `draft` is the commit text, while `decide`'s empty flag
    reads the input. They differ only when the whole input is `phony`, which
    this schema cannot produce.
- **Dimension 2.** No new commit or candidate path. The guard writes only an
  empty `prompt` and `caret_pos`.
- **Dimension 3.** Check 2 still runs first on every event and clears the
  prompt. The Esc return comes after the clear, so the prompt goes; the mutant
  that returns before the clear dies. Check 1 is unchanged.
- **Dimension 4.** The new module-level names are `ACTS_ON_DRAFT`, a constant
  table, and `caret_inside`, a pure function. No session state.
- **Dimensions 5 and 7.** Unchanged by this round.
- **Dimension 6.** I re-ran the author's 29 mutants: the control passes and all
  29 are killed, round 1's three wiring mutants included. My own 13 are in the
  third suggestion.
- **Dimension 8.** New comments and their anchors:
  - `:26-31`: F15 and `Compose`. Incomplete (yellow 2, first suggestion).
  - `:54-57`: S11 row 5b and this review. Overstated for the click case (second
    suggestion).
  - `:66-68`: no anchor that holds (yellow 2).
  - `session.lua:15-17`: F15.
- **Docs.**
  - decisions.md records both of the user's choices and the option not taken.
  - The Task 10 note carries both smoke rows.
  - F15 is labelled a source reading at 1.16.0, and the version table says
    F13–F15.
  - Nothing is presented as measured.
  - Needed corrections: yellow 2, and the first two suggestions.
- **Commands.**
  - `lua tests/test_glue_load.lua` gives
    `test_glue_load: 2 modules OK, shared is lazy and stateless`.
  - `lua tests/test_processor.lua` gives `test_processor: 68 assertions OK`.
  - `scripts/run_tests.sh` exits 0: backend 126, config 75, decide 60,
    glue_load ok, decode 88, encode 10, processor 68, session 36, state 17.
  - `.githooks/pre-commit` exits 0.
  - Afterwards, `git status --short` is unchanged, and so are the hashes of
    `git diff --cached` and `git diff`.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| `lua tests/test_glue_load.lua` passes (both modules load with the right export shape) | ok | Passes. The file is unchanged since round 1 and identical to the plan |
| `engine:commit_text` appears only in `ime_translate_processor.lua` | ok | grep over `rime/`: `:93` and `:100` only. The guard adds none |
| `shared` has no fsm / phase | ok | `shared.lua` is unchanged. Asserted in `test_glue_load` |
| Both invalidation checks are present: `decide`, and the top of every processor event, which also clears the prompt | ok | `decide.lua:54`; `processor.lua:51-53`, before `decide`. The prompt is cleared before the Esc return |
| Every `ctx:clear()` is preceded by a `commit_text` (never eat text) | ok, in substance too (source reading, not measured) | `:93→95` and `:100→102`, both behind the caret guard at `:71`. With the caret at the end, the commit text is the whole input |

### Verdict
0 red / 2 yellow / 3 green: no red, clear to close once each yellow is fixed or
deferred with a one-line reason. Yellow 1 is a behaviour choice, so the user
makes it. Nothing here has been measured in Squirrel; Task 10's smoke rows own
that.

### Author's response (Task 9, round 2)

- **Yellow 1: deferred to Task 10 by the user.** Task 10's revision note now
  carries the smoke row:
  - With the prompt showing and the last segment open, click the highlighted
    candidate.
  - Expected by source reading: the prompt vanishes, and the next Enter commits
    English that is no longer on screen.
  - If it is measured so, it is fixed before Task 10 closes, with this round's
    option (a) or (b).
- **Yellow 2: fixed.** The false claim is corrected in all four places:
  - the processor's comment
  - the test (the fake now returns the whole draft at caret 0, and the case
    asserts that the extra press only moves the caret and the next one commits
    the whole draft)
  - §5.2
  - decisions.md, whose correction is dated and keeps the wrong sentence
    visible as history

  F15 now records the confirmed-position branch and the `caret_pos` setter chain
  from this round. Its version line says F15 was read at 1.16.0.

  The mutant "empty read from the commit text" now survives, as this round
  predicted. On the engine it is equivalent.
- **Green 1: done.** The processor's comment and §5.2 now qualify "like native
  Return" for the caret only:
  - A non-default highlight before the caret falls back to the default.
  - It is shown before the next press and never committed unseen.

  Task 10's caret row gains "highlight a non-default candidate, then Enter".
- **Green 2: done.**
  - §5.2's Esc paragraph now says the Esc is taken whenever check 2 fires on an
    Esc with a draft left.
  - If the edit already removed the prompt, that Esc does nothing visible, and
    nothing is lost.
  - The processor's comment says "may still be on screen".
- **Green 3: two of the six survivors are now pinned.**
  - Enter in result with the caret moved inside and the draft unchanged
    commits nothing, moves the caret and drops the prompt.
  - An Esc carrying the Lock bit after a no-key edit is taken.

  All three guard mutants and the `modifier == 0` Esc mutant die. The release
  check stays defensive.
- **Notes outside: Shift+Esc.** It is on Task 10's revision list, with the
  source-reading expectation: the Shift press voids the translation, then the
  native cancel wipes the draft, as Esc in idle does.
- **Mutation check.** 33 mutants on a scratch copy, with the control run
  first:
  - 32 killed.
  - The one survivor is the equivalent "empty from the commit text".
- `test_processor` is at 75 assertions. `scripts/run_tests.sh` exits 0.

---

## Task 10: Schema wiring + installer + smoke — round 1

Range: `34b7e09..HEAD` is empty, because Task 10 is staged, not committed. It was
reviewed as `git diff --cached` (11 files). `git diff` is empty, so the index
and the working tree are the same. `progress.json` is ledger state and was not
reviewed.
Time: 2026-09-22T00:29Z

Evidence labels follow the `design-review` skill. **Agent-observed** means the
smoke run's readback, screenshot or log; no human watched any row. Upstream
read this round: librime tag `1.16.0` (`gear/punctuator.cc`,
`gear/switch_translator.cc`, `switcher.cc`, `engine.cc`, `composition.cc`,
`lever/deployment_tasks.cc`) and librime-lua master `src/types.cc`.

### 🔴 Must fix
- **`docs/smoke-report.md:16` and `:69-92`: the 👁 gate rows are reported as
  passed with no human observation, so acceptance item 1 is not met.**
  - Who observes is fixed in two places. decisions.md, "Task 10 revised before
    start", says "The user watches the rows marked 👁: the first loop, the
    mouse rows, and WeChat's send". Plan Step 6 says "👁 means the user
    watches". Together they make the user the observer for rows 4, 5, 21, 22,
    23 and 27. CLAUDE.md lists "A human observes the real machine" among the
    red lines that no tool checks.
  - No human watched any row. That comes from the brief and the report's own
    Observed column.
    - Two rows say so: row 4 (`:69`) and row 21 (`:86`), both "Pending the
      user…".
    - Four rows do not: rows 5, 22, 23 and 27 (`:70`, `:87`, `:88`, `:92`)
      say **pass**, `agent`, with no pending note.
    - Line 16 states "The user watches the rows marked 👁" as though it
      happened.
  - Row 4's "user in use" is the agent reading the debug log of the user's
    own typing. The translate/commit pairs at 16:47–16:54 and 17:01–17:08 were
    counted here, not read. That is good evidence that the loop works. It is
    not the user reporting what row 4 asks.
  - **Scenario.** `/task-done` reads the table and finds every gate row passed
    except row 21's wheel. It closes Task 10. No human then ever saw row 22,
    the one gate row that failed and changed the processor. No human saw
    WeChat's "not sent" either.
  - **To clear**, one of two things:
    - The user watches rows 5, 22 (after the fix), 23 and 27, confirms row 4,
      and does row 21's wheel.
    - The user explicitly accepts agent observation for those rows. That is
      recorded here and in decisions.md, because it changes a standing rule.

    Either way, rows 5, 22, 23 and 27 and line 16 are relabelled to say what
    actually happened.

### 🟡 Should fix
1. **"Measured" is written for agent-only observations.** The `design-review`
   skill (lines 65-68) says measured means "a person saw it on the machine",
   and "Only a human at the machine produces the fourth". The word appears in:
   - `rime/lua/ime_translate_processor.lua:94-95`: "(Task 10 smoke row 22,
     measured)"
   - `docs/design/architecture.md:288`: "The opposite case, measured (Task 10
     smoke row 22)"
   - `docs/design/architecture.md:335`: "Measured in Task 10's smoke checks"
     (rows 10, 14, 18-19, 22-23)
   - `docs/design/decisions.md:466` ("Smoke row 22 measured …") and `:484`
     ("Re-measured on the machine")
   - `docs/smoke-report.md:51`: "`schema_list/+` works (measured)"

   **Scenario.** Task 12, or a `/design-review`, reads §6.2's "measured" as
   settled human evidence. It never asks for row 22 to be watched.

   **Fix.** Write "observed by the agent (smoke row N)" until a human has
   watched. The alternative is a recorded decision that Task 10's agent
   readback counts as measured. Rows the user then watches can take the word
   back.
2. **`scripts/install.sh:21-27`: a failed copy is reported as installed, and
   the run exits 0.**
   - **Why.** Every call of `put` sits on the left of `&&` or `||`, or inside
     an `if` (`:32`, `:35`, `:53`, `:59`, `:74`). There, bash suspends
     `set -e` for the whole function body. So a failing `cp` at `:25` falls
     through to `echo "installed $dest"` and `return 0`. A failing backup `cp`
     at `:24` falls through to overwriting the file with no backup.
   - **Sandbox.** `HOME` was redirected, and `launchctl` and Squirrel were
     stubbed. `lua/ime_translate/state.lua` and the schema were made
     read-only. For both files, the run printed `cp: … Permission denied` and
     then `installed …`. It set `lua_changed`, printed "Install complete" and
     exited 0. `state.lua` still held its old content.
   - **Scenario.** An earlier `sudo ./scripts/install.sh` left one file in
     `~/Library/Rime/lua/` owned by root. The installer claims the new module
     is in place, and the user restarts Squirrel. The old processor keeps
     running, for instance one without the row-22 guard.
   - **Fix.** Make a copy failure fatal inside `put`, for example
     `cp … || { echo "failed: $dest" >&2; exit 1; }`. `exit` leaves the
     script even where `set -e` is suspended.
3. **`scripts/install.sh:81-84`, ahead of `:86-95`: a failed
   `launchctl bootstrap` stops the run after the Lua is copied and before the
   restart notice. A rerun never prints that notice.**
   - **Sandbox.** With `bootstrap` stubbed to fail, the run exited 5 after
     `Bootstrap failed: 5: …`. There was no `--reload` and no "Lua changed"
     notice. The Lua files were already new, so a second run found them
     identical. It left `lua_changed=0` and said nothing about restarting.
   - **Scenario.**
     1. The user once ran
        `launchctl disable gui/$UID/local.ime-translate.translate-serve`, so
        `bootstrap` fails. (Unverified on this machine. Any other bootstrap
        failure does the same.)
     2. They fix it, rerun, and get a clean "Install complete".
     3. Squirrel keeps the old Lua modules. install.sh's own notice says it
        does so until it restarts.
   - **Fix.** Reload Squirrel and print the notice before the launchd block,
     or let the launchd block warn and continue. The IME's install does not
     depend on the service.
4. **`rime/luna_pinyin_translate.schema.yaml:31-32`: `full_shape` has no
   `reset`, so in full-width mode `,` `.` `?` `!` `;` `:` and `^` commit the
   whole draft.**
   - **The gap.** Change 4 made only `half_shape`'s marks plain strings.
     Change 6 (`:40`) resets `ascii_punct` because change 4 relies on it.
     `full_shape` defeats change 4 the same way and is left open.
   - **The chain**, a derivation from source reading:
     - `punctuator.cc` `PunctConfig::LoadConfig` (:24-25) uses
       `punctuator/full_shape` when the option is on.
     - The built schema's `full_shape` map keeps `{ commit: … }` for all seven
       marks.
     - `AutoCommitPunct` (:204-209) calls `Context::Commit()`.
   - **Two ways the option turns on:**
     - `Control+Shift+3`. It comes from the preset's `numbered_mode_switch`
       (`key_bindings.yaml:46`) and is in the built schema. It sits next to
       the `Control+Shift+4` that this schema's own comment offers for the
       script.
     - The full-width entry in the switcher menu, in any schema. `full_shape`
       is in `default.yaml` `switcher/save_options` (line 23), so
       `Switch::Apply` saves the choice (`switch_translator.cc:62-64`).
       `ConcreteEngine` restores it in every later session (`engine.cc:88-89`).
       `InitializeOptions` (:384-386) resets only switches that declare
       `reset`.
   - **Scenario.** The user picks full-width once in `luna_pinyin_simp`. From
     then on, in the translation schema, `jintianyoudianlei` followed by `,`
     puts `今天有点累，` into the app in Chinese. Nothing is lost, but every
     sentence with punctuation skips the translation, with no hint why.
   - **Settle it by measurement.** In the translation schema, press
     `Control+Shift+3`, type a draft, then `,`.
   - **Fix.** Add `reset: 0` to `full_shape`, as change 6 does for
     `ascii_punct`, or make the marks plain strings under `full_shape` too.
     This is a schema change, so it is the user's call.
5. **Smoke row 16 contradicts `architecture.md` §5.1, and nothing records the
   conflict.**
   - §5.1 (`:149-150`) says "The normal schema is the default at login".
   - Row 16 (`smoke-report.md:81`) records "A new document starts in the
     translation schema". `upstream.md:117-118` already said so.
   - Source reading, `switcher.cc`: `SetActiveSchema` (:165-170) saves
     `var/previously_selected_schema`. `CreateSchema` (:178-181) starts every
     new session in it.
   - The live `user.yaml` holds `luna_pinyin_translate` right now.
   - **Scenario.** After one `Control+Shift+T`, every new session starts in
     the translation schema, across restarts too. Someone who trusts §5.1
     types a Chinese commit message in a fresh terminal and presses Enter. It
     translates instead of committing. With a cloud backend configured, that
     sentence goes to the vendor. The config's cloud note ("every Chinese
     sentence you translate goes to a third party") assumes the user chose to
     translate it.
   - **Not a drop-in fix.** `switcher/fix_schema_list_order` exists (`:179`,
     `:290`), but it would start sessions in `luna_pinyin`, the first entry,
     not in `luna_pinyin_simp`.
   - Correcting §5.1 or changing the behaviour is a `/design-review` item.
     Either way, record it rather than leave two design documents
     disagreeing.
6. **`rime/ime_translate.yaml:7`: the Keychain command puts the API key on the
   command line.**
   - `security add-generic-password … -w <your-key>` saves the key to the
     shell history (`~/.zsh_history` under zsh). It also shows in `ps` while
     it runs.
   - `man security` says: "-w password … Put at end of command to be prompted
     (recommended)".
   - **Scenario.** The user pastes their key into the command as shown. It
     sits in plain text in `~/.zsh_history`. Dotfiles synced to GitHub then
     leak it. That is the very leak the WARNING two lines above describes.
   - **Fix.** Use
     `security add-generic-password -s ime-translate -a <account> -w`, with
     `-w` last so that `security` prompts. Make the same change at
     `docs/design/backend.md:41`, which the file copies.

### 🟢 Suggestions
- **`rime/lua/ime_translate_processor.lua:110-115`: the error-phase twin of
  row 22.**
  - The same click on the highlighted candidate removes
    `  ✗ 翻译服务未启动`, while the phase stays `error`. Enter then commits the
    Chinese draft.
  - Nothing unseen is committed, because the Chinese is on screen. But the
    screen now looks idle, and in idle §5.2 says Enter translates.
  - **Scenario.** The user restarts the service, clicks the candidate, and
    presses Enter expecting English. Chinese lands in the app.
  - This is a derivation from row 22's mechanism, not measured. If it
    matters, apply the same "on screen" condition to `commit_draft` in
    `error`. At the least, §6.2's new paragraph could name the case.
- **`rime/lua/ime_translate_processor.lua:97-100` writes no log line.** With
  `debug_log` on, the re-show shows up only as a missing second `translate`.
  The row-22 re-measure had to rely on the readback for it. If Task 11 meets
  an application where Enter keeps re-showing, the log cannot tell a re-show
  from a lost key. One `log(S, …)` in the branch would fix that.
- **`docs/smoke-report.md`: form and completeness.**
  - Row 27 (lines 92-95) puts a list inside a table cell. That ends the
    Markdown table. Rendered, row 27 loses its Observed cell, and row 28
    (line 96) prints as plain text.
  - `docs/README.md`'s index lists `spike-report.md` and `compat-matrix.md`,
    but not this report.
  - The deploy at 16:58:22 was interrupted, and the report does not mention
    it.
    - The fix's install ran `--reload`, and Squirrel was quit within two
      seconds. The deploy logged `invalid schema definition` for all ten
      schemas, and its INFO log ends mid-line.
    - It was harmless. `last_build_time` is written only when
      `WorkspaceUpdate` finishes (`deployment_tasks.cc:252`), no `.yaml` had
      changed, and both 17:09 deploys logged 10 success, 0 failure.
    - But `$TMPDIR/rime.squirrel/rime.squirrel.ERROR` still points at that
      log. Task 11 will find "invalid schema definition in
      …/luna_pinyin_translate.schema.yaml" there. One line in the report
      saves that chase, and install.sh's notice could say to wait a moment
      after the reload.
- **`rime/ime_translate.yaml:10-11`** still says changes take effect after
  `--quit`. The smoke run found that Squirrel comes back only on a focus
  change. `install.sh:93-94` was corrected for that, but this comment was
  not. **Scenario.** The user edits the config, runs `--quit`, and keeps
  typing in the same app. The IME does not come back.
- **The page size differs across the pair.**
  - The machine's `luna_pinyin.custom.yaml` sets `menu/page_size: 9`. That
    reaches `luna_pinyin_simp` through its include (built: 9), but not this
    schema (built: 5), because change 7 gives the schema its own
    customization hook.
  - Row 16 saw it: 9 candidates, then 5. Candidates 6 to 9, one key away in
    `luna_pinyin_simp`, need a page turn here.
  - This is machine configuration. If the user wants the pair to match, a
    `luna_pinyin_translate.custom.yaml` on the machine fixes it.

### Deviations from the plan
- **The five deliverables.** I extracted the plan's five code blocks and
  diffed each against its deliverable. Four are byte-identical. `install.sh`
  differs only at `:93-94`, the closing message. The smoke report's findings
  and deviations explain it: Squirrel relaunches on a focus change, which the
  agent observed. It is an improvement.
- **The processor and its test** are outside Task 10's file list. Two places
  explain them: decisions.md, "Task 10 smoke: Enter commits only a
  translation on screen", and the report's deviations. They are the user's
  chosen fix for row 22, and an improvement (see What was walked).
- **Step 6 substitutions.** The report states every one of them, and each
  keeps what its row tests:
  - Row 12 used a closed port, because the `bootout` was declined.
  - Row 15 used a second TextEdit document instead of Notes. It is a second
    input client, and the first document received raw pinyin, as S12
    predicts.
  - Row 17 used a posted keycode.
  - The stub ran outside `/tmp`.
- **Step 1's stock diff** is not in the report. I ran it. With comments
  stripped, the only differences from the stock `luna_pinyin.schema.yaml` are
  the schema metadata and the seven marked changes.
- **Step 7, the commit,** has not been done. It waits on this review.

### What was walked
- **Dimension 1.** The only `commit_text` calls in `rime/` are
  `ime_translate_processor.lua:104` and `:111`. Each is followed by
  `ctx:clear()`, at `:106` and `:113`. The new branch at `:97-100` shows the
  prompt and returns `kAccepted`, with no clear and no commit.
  - `back()` there cannot be nil:
    - `commit_translation` needs `result` and a non-empty input (`decide`).
    - Check 2 has already passed, so the draft equals the snapshot.
    - A non-empty input always has a segment, because `fallback_segmentor`
      covers whatever the other segmentors leave (derivation).
    - If it ever raised, `lua_gears` would turn that into `kNoop`, and native
      Return would confirm (Task 9, round 1). No text is lost either way.
  - The installer never touches a live draft. Its notice warns about open
    drafts before `--quit`.
- **"Commits unseen."** The guard compares `back().prompt` with
  `session.prompt(ctx)`.
  - `Composition::GetPrompt` (`composition.cc:98-99`, 1.16.0) displays
    exactly `back().prompt`, and `GetPreedit` inserts it at the caret
    (:85-87). So the guard checks what is on screen.
  - librime-lua's `Segment` has both a getter and a setter for `prompt`
    (`types.cc:187`, `:200`).
  - The live run exercised both. The debug log shows three translate/commit
    pairs at 16:58:34–16:58:49, right after the fix was installed (rows 4-6
    re-run). It shows one translate and one commit at 17:08:24–26 (row 22's
    re-show, then the commit). I counted events only and read no content.
- **Dimension 2.** The schema has one Lua component,
  `lua_processor@ime_translate_processor`, and it comes first in the built
  schema. There is no translator or filter. `simplifier` and `uniquifier` are
  stock and do not touch the prompt.
- **Dimension 3.** Check 1 (`decide.lua:54`) and check 2
  (`ime_translate_processor.lua:53-63`) are unchanged. The guard is an extra
  condition on the commit only.
- **Dimension 4.** No module state was added. The guard reads the Context.
- **Dimension 5.** No new shell string in Lua. `install.sh`'s quoting held
  with a `HOME` containing a space (the sandbox used `home dir`).
- **Dimension 6.** On a scratch copy, the new test fails under three mutants:
  - guard removed: #77, "commits nothing unseen"
  - guard without `return`: #77
  - guard that re-translates: #79, "without a second backend call"

  The unmodified copy passes 81.
- **Dimension 7.** `config.load` on the shipped `ime_translate.yaml` gives 0
  warnings, with these values:
  - `libretranslate` at `http://127.0.0.1:8989`, which is the plist's port
  - 1500 and 2000
  - `debug_log` false, `allow_remote` false
  - `api_key_account` empty
- **Dimension 8.** The processor's comment rests on row 22 (agent-observed;
  yellow 1) and on the source reading in Task 9, round 2. The getter's
  anchor is above.
- **Dimension 9.** Nothing that v1 excludes.
- **Schema and D5.** The built schema matches the report:
  - the processor first
  - 32 `key_binder` bindings, with the preset's `Control+Shift+T` before this
    schema's
  - `zh_simp` with `reset: 1`, and `simplifier/option_name: zh_simp`
  - `,` → `，` as a plain string

  The built `default.yaml` `schema_list` is the eight stock schemas plus this
  one. `luna_pinyin_simp` is `__include: luna_pinyin.schema:/` with `zh_simp`
  `reset: 1` and the two toggles, which is what change 3 copies.
- **Installer, in a sandbox.** A copy of `install.sh` had `SQUIRREL` and
  `TRANSLATE` pointed at stubs, with `launchctl` stubbed on `PATH` and `HOME`
  redirected.
  - Run 1 installed the 8 Lua files and kept `ime_translate/`. It bound
    `rime.lua` and installed the schema, `default.custom.yaml`, the config and
    the plist, then started the service.
  - Run 2 printed only "Squirrel: redeployed" and the closing text. The file
    tree hashed the same (13 files).
  - A foreign `default.custom.yaml` and a user `ime_translate.yaml` were left
    untouched, and the merge hint printed.
  - A `rime.lua` with no trailing newline got the binding on its own line.
  - The read-only and bootstrap-failure runs are yellows 2 and 3.
- **Live machine, read-only.**
  - Every installed Lua file, the schema, `default.custom.yaml` and the plist
    are `cmp`-identical to the repo.
  - `~/Library/Rime/ime_translate.yaml` is identical to the shipped default,
    so `debug_log` is off again.
  - `translate --serve` has run as a child of launchd (PPID 1) since 08:43.
    Squirrel has run since 17:09:20.
  - Rime logs: the 08:43 install deploy has only the `grammar.yaml` and
    first-build warnings, as reported. The 16:58 deploy is the suggestion
    above. The 17:09 deploys logged 10 success, 0 failure.
- **Commands.**
  - `scripts/run_tests.sh`: 9 PASS (backend 126, config 75, decide 60,
    glue_load ok, decode 88, encode 10, processor 81, session 36, state 17).
  - `.githooks/pre-commit`: exit 0.
  - `git status --porcelain=v2` was identical before and after. The only
    change I made is this entry.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every smoke check in Step 6 passes: gate rows as specified, record rows once written down | **not met** | Gate rows 1-3, 6-13, 15, 16, 18, 19 and 28 pass on agent observation, which the rule allows. Row 17 is gate "if possible" and passes on a posted keycode. Record rows 14, 20, 24, 25 and 26 are written down (24 and 26 as emulated `flagsChanged`, labelled). No human has observed 👁 rows 4, 5, 21, 22, 23 and 27, and row 21's wheel trigger was not reproduced (the red) |
| install.sh is idempotent and never overwrites user config | ok | Sandbox: two runs gave an identical tree, and the second printed no `installed`, `bound`, `wrote` or `started` line. A user `ime_translate.yaml` and a foreign `default.custom.yaml` were left untouched. Failure paths: yellows 2 and 3 |
| install.sh preserves the `ime_translate/` subdirectory | ok | Sandbox and live: `lua/ime_translate/` holds the 6 modules, and `lua/` holds the processor and `shared`, identical to the repo |
| `rime/ime_translate.yaml` contains no secret, only `api_key_account` | ok | `config.load`: `api_key_account` empty, 0 warnings, and no key-shaped string. The leak in the Keychain instruction itself is yellow 6 |

### Verdict
1 red / 6 yellow / 5 green: the task **cannot** be marked done.

The code itself carries no red. No path eats text, and the guard commits only
what `GetPrompt` displays. The red is about evidence. The 👁 gate rows need
the user's eyes, or the user's recorded acceptance of the agent's. Row 21's
wheel trigger is also still open.

### Author's response (Task 10, round 1)

- **Red: settled by the user's decision.** The user accepts agent observation
  for the 👁 rows (4, 5, 22, 23, 27). Recorded in decisions.md, "Task 10
  review, round 1".
  - The smoke report now says so where it described the method. Those rows are
    labelled "agent, accepted".
  - Row 4's "user in use" is restated for what it was: the agent reading the
    debug log of the user's own typing, not quoted.
  - Row 21's wheel trigger stays unverified.
  - Row 27's cell is one line, so the table holds all 28 rows.
- **Yellow 1: fixed.** "Measured" is replaced by "observed by the agent" at
  every place the round listed:
  - the processor comment
  - architecture.md §6.2 and §6.4
  - decisions.md, both lines
  - smoke-report.md line 51
- **Yellow 2: fixed.** A failed backup or copy inside `put` prints
  `FAILED to …` and `exit 1`s. Sandbox check, with the installed `state.lua`
  read-only: `FAILED to install …/state.lua`, exit 1, no "Install complete".
- **Yellow 3: fixed.** A failed `launchctl bootstrap` prints
  `FAILED to start … the IME is installed, the local backend is not`, sets the
  exit status, and the run goes on to `--reload` and the restart notice. Sandbox
  check, with `bootstrap` stubbed to fail with 5: the message, `redeployed`, the
  notice, exit 1.
- **Yellow 4: fixed, as the user chose: plain strings under `full_shape` too.**
  - The built schema holds `",": "，"` under both shapes.
  - Re-run by the agent: the switcher showed `半`, `Control+Shift+3` turned it
    to `全`, and in full-width `jintianyoudianlei`, space, `,` gave the draft
    `今天有点累，` with nothing committed. Then `半` was restored.
  - This deviates from the plan, which is immutable once started. It is
    recorded in the smoke report and decisions.md.
- **Yellow 5: fixed by the user's decision.** §5.1 is corrected: new sessions
  start in the previously selected schema. **D6 is opened** in the open table,
  blocking nothing, on whether to force new sessions into `luna_pinyin_simp`.
- **Yellow 6: fixed.** `security add-generic-password … -w`, with `-w` last,
  in `rime/ime_translate.yaml` and `docs/design/backend.md:41`. The installed
  copy of the config is the user's and is not overwritten; it still shows the
  old comment.
- **Greens:**
  - **The error-phase twin** is named in §6.2's new paragraph, as a derivation.
    No code change: the Chinese that Enter commits there is on screen.
  - **The re-show branch** now logs `translation was off screen: shown again`.
  - **The smoke report** is fixed: row 27's table break is gone, the report is
    in `docs/README.md`'s index, and the 16:58 interrupted deploy is noted.
  - **The config's `--quit` comment** now says a restart needs a focus change.
  - **The 9-versus-5 candidates** are noted. No per-schema `page_size` was
    added, since that is the user's setting.
- **Also added to the smoke report**, at the user's question after the run:
  mixed Chinese and English in one draft, observed by the agent.
  - A capital first letter, then space, works (`请你整理一个Readme文件`).
  - Left Shift's inline English did not trigger from a posted key and is
    unverified with a physical key.
  - Right Shift is `commit_text`: a config reading.
- `scripts/run_tests.sh` exits 0, and `test_processor` is at 81 assertions. The
  project checks pass on every changed file.

---

## Task 10: Schema wiring + installer + smoke — round 2

Range: `34b7e09..HEAD` is still empty, because Task 10 is staged, not
committed. It was reviewed as `git diff --cached` (14 files). `git diff` is
empty, so the index and the working tree are the same. Round 1 reviewed the
same set. This round checks each round-1 finding against its fix, then walks the
fixes for anything new. `progress.json` is ledger state and was not reviewed.
Time: 2026-09-22T01:52Z

Evidence labels as in round 1. No machine was driven. Read this round: the
staged diff, `~/Library/Rime/` and its `build/`, `user.yaml`,
`$TMPDIR/rime.squirrel/`, event counts (never content) from
`~/Library/Logs/ime_translate.log`, and librime tag `1.16.0`
`gear/punctuator.cc`.

### Round 1, finding by finding
| Round 1 | Status | Evidence |
|---|---|---|
| 🔴 👁 gate rows reported as passed with no human observation | **partly closed** | Rows 4, 5, 22, 23 and 27 are relabelled "agent, accepted", and `decisions.md:494` records the user's acceptance for exactly those five. Row 21 is still open: red 1 below |
| 🟡 1 "measured" for agent-only observation | closed at every listed place; one place my list missed | Processor :95, architecture.md §6.2 and §6.4, decisions.md and `smoke-report.md:54` now say "observed by the agent". The missed place is yellow 2 below |
| 🟡 2 a failed copy reported as installed | closed | Sandbox B: a read-only installed `state.lua` gives `FAILED to install …/state.lua`, exit 1, no "Install complete", and the old content stays. The fix opens yellow 1 below |
| 🟡 3 a failed bootstrap stops the run before the notice | closed | Sandbox C: `Bootstrap failed: 5`, then `FAILED to start …`, `--reload`, the "Lua changed" notice, the closing text, exit 1. A rerun with bootstrap still failing reports the failure again, so a rerun does not hide it |
| 🟡 4 `full_shape` commits the draft | closed | Built schema: all seven marks are plain strings under `full_shape`. The only `{ commit: … }` left in either shape is full-width `" "`, and it cannot reach a draft: `Punctuator::ProcessKeyEvent` returns kNoop for space while composing unless `punctuator/use_space` is set (`punctuator.cc:109`, 1.16.0; not set in the build). `user.yaml` holds no saved `full_shape`, so the re-run left it half-width. The re-run itself rests on readback only: `debug_log` was off (the installed config's mtime is 17:09, and the log ends at 17:08) |
| 🟡 5 §5.1 against row 16 | closed | §5.1 corrected (`architecture.md:152-161`). D6 is in the open table. `open-decisions.sh` parses it (`blocks -`, `waits for -`), `progress.sh decisions` lists it, and `open-decisions.sh blocking 001-zh-en-ime` returns nothing for 10, 11 or 12. One anchor gap: green 1 |
| 🟡 6 `-w <key>` on the command line | closed | `rime/ime_translate.yaml:7-8` and `docs/design/backend.md:41` both end in `-w`. The machine's installed copy is green 3 |
| 🟢 all five | addressed | The error-phase twin is named in §6.2, labelled a derivation. The re-show branch logs (processor :100). Row 27 is one line: the table is 30 lines of 5 pipes each. The README index has the report. The 16:58 interrupted deploy is noted (`smoke-report.md:118-120`); `rime.squirrel.ERROR` still points at it. The config's focus-change line is in (:13). The page size is noted |

### 🔴 Must fix
- **Acceptance item 1 is still not met. Gate row 21 has not been run as
  specified, and nothing records the user letting Task 10 close without it.**
  This is the round-1 red, narrowed to one row.
  - **What the plan asks.** Row 21 (`task-10-wiring.md:505`) is "scroll the
    candidate window with the mouse wheel, then Esc", a gate 👁 row.
  - **What the report records.** `smoke-report.md:89` passes "the Esc rule" on
    a different trigger, a click on the 3rd candidate. It records the wheel as
    "not reproduced … Pending the user with a real trackpad", and Observed as
    "agent; user pending".
  - **The record disagrees with itself.**
    - The user's acceptance (`decisions.md:494`) names rows 4, 5, 22, 23 and
      27. It does not name 21.
    - Yet `smoke-report.md:89` labels row 21's Esc half "agent, accepted".
      `:16-18` says the acceptance covers "the rows marked 👁", and 21 is one.
    - `decisions.md:499`, "Row 21's wheel trigger stays unverified", does not
      say whether Task 10 may close that way. The report says it is pending.
      If Task 10 closes now, the pending item has no owner: no task, no open
      decision.
  - **Why the click does not stand in for the wheel.**
    - The Esc rule exists for exactly this case. The Task 9 decision that made
      it (`decisions.md:398-402`) names "paging the candidate window with the
      mouse" as its example of a no-key edit. The processor's comment at
      :56-59 rests on the same premise.
    - A click is a known no-key edit. With a click, check 2 fires on the Esc,
      the rule at :60-62 takes it, and the draft stays.
    - Whether a wheel page arrives with no key is what nobody has seen. If
      Squirrel delivers it as a key, `decide` returns `invalidate_and_pass` on
      that key and the prompt goes. The following Esc then finds the phase
      `idle`, so it reaches librime's native cancel. S11 row 5b recorded that
      cancel clearing the whole draft (`spike-report.md:243`).
    - Both branches are derivations. The row exists to tell them apart.
  - **Scenario.**
    1. `/task-done` reads row 21 as passed, since it says "pass" and
       "accepted", and closes Task 10.
    2. Task 11 inherits no note that the wheel was never tried.
    3. The user is in state B with a translation showing. They page the
       candidate window with the trackpad, then press Esc to go back to
       editing.
    4. If the key branch is the real one, the sentence is gone.
  - **To clear**, one of two things:
    - **The user does the wheel once.**
      - In TextEdit, in the translation schema, type `jintian`, space,
        `buguo` (state B), then Enter.
      - With the prompt and the candidate window showing, two-finger scroll
        over the window until it pages. Then press Esc.
      - Pass: the draft stays in the input box, underlined, with nothing
        committed.
      - Also write down whether the prompt vanished on the scroll. That shows
        which branch Squirrel takes.
    - **Or the user states that Task 10 closes with row 21's wheel
      unverified**, and says where it goes next (Task 11's matrix, or
      nowhere).
      - decisions.md then says so.
      - `smoke-report.md:89` and `:16-18` stop calling it "pending", and
        stop calling "accepted" what was not accepted.

### 🟡 Should fix
1. **`scripts/install.sh:57`, `:63`, `:80`: since the yellow-2 fix, a failed
   copy of the schema, `default.custom.yaml` or the plist exits after the Lua
   is already new. That is before `--reload` and the restart notice
   (`:96-104`). A rerun then finishes clean and never says to restart
   Squirrel.**
   - This is round 1's yellow 3 again, now reached through `put`'s new
     `exit 1`.
   - For the plist it also contradicts `:76-77`, "A launchd failure is
     reported and the run goes on". A failed plist copy is a launchd-side
     failure, and the run stops.
   - **Sandbox.** `HOME` was redirected, and `launchctl` and Squirrel were
     stubbed.
     - F1, `~/Library/LaunchAgents` not writable. All eight Lua files are
       `installed`, `rime.lua` is bound, and the schema and
       `default.custom.yaml` are installed. Then comes
       `FAILED to install …/local.ime-translate.translate-serve.plist` and exit 1, with
       no `--reload` and no notice.
     - F2, permissions fixed, rerun. The plist is installed, the service
       started, then `redeployed`, "Install complete", exit 0. There is no
       "Lua changed" notice, because every Lua file is now identical.
     - E1/E2, a read-only installed schema, gave the same result.
   - **Scenario.**
     1. Another installer has left `~/Library/LaunchAgents` owned by root.
        (Unverified here: on this machine it is the user's own account.)
     2. The user pulls a change to the processor, for instance this task's
        row-22 guard, and runs `install.sh`. It prints the FAILED line.
     3. They fix the ownership and rerun, and get "Install complete".
     4. Squirrel keeps the old processor until something restarts it. That
        processor still commits a translation that is no longer on screen.
   - **Fix.** Print the restart notice from an `EXIT` trap whenever
     `lua_changed=1`, so that every exit path says it, `put`'s `exit 1`
     included. Alternatively, treat a failed plist copy like a failed
     bootstrap: warn, set `status=1`, and go on. Only the trap also covers the
     schema and `default.custom.yaml`.
2. **`tests/test_processor.lua:256` still says "Task 10 smoke row 22
   (measured)".**
   - Round 1's yellow 1 listed the places the word appeared and missed this
     one. The fix followed that list.
   - `decisions.md:496-497` now says "'measured' is not used for them".
   - **Scenario.** Whoever next asks how row 22 was established, Task 12 or a
     `/design-review` of §6.2, starts from the regression test that pins it.
     It says measured.
   - **Fix.** One word, for example "observed by the agent; accepted for
     Task 10".
   - The diff's other added uses of "measured" were checked and are right:
     - the plist's Task 6 note
     - the schema's two references to the spike
     - decisions.md quoting the user's earlier condition
     - §6.4's "Not measured"

### 🟢 Suggestions
- **The anchor for §5.1's correction.**
  - `docs/design/architecture.md:154-155` anchors "source reading,
    `switcher.cc`" on upstream.md §15.4.
  - §15.4 holds only a parenthetical, "(Squirrel opens a new session in the
    previously selected schema)". It sits inside a derivation about the
    script and names no symbol.
  - No F-row in §15.2 covers it. The reading exists only in this log: round 1,
    yellow 5, `Switcher::SetActiveSchema` saves
    `var/previously_selected_schema` and `Switcher::CreateSchema` reads it.
  - **Scenario.** D6 is settled through `/design-review`, which re-reads
    upstream for every claim. The link sends it to a sentence that cites
    nothing. An F16 row naming those two symbols fixes it.
- **D6's cell** (`decisions.md:23`) says an Enter meant for a newline "would
  then send the sentence". §5.1 says "to the vendor". Without those two words,
  the line `progress.sh decisions` prints reads like the IME sending a
  message. That would be a breach of the §2 red line, not the privacy cost D6
  is about.
- **The machine's installed config still shows the old command.**
  - `~/Library/Rime/ime_translate.yaml:7` still says `-w <your-key>`. The
    author's response notes this.
  - Its diff against `rime/ime_translate.yaml` is only the two comment hunks
    from this round, and it has no non-comment line. So it holds no user
    edits, and replacing it with the shipped file loses nothing.
  - **Scenario.** This machine is where the user will set up a cloud key.
    The file they open to do it is the one the installer laid down, and it
    still shows the command that puts the key in `~/.zsh_history`.
  - It is the user's file, so this is the user's call.
- **`scripts/install.sh:114` points at a note the plist does not have.**
  - The line reads "Download the Chinese -> English translation model (see
    the plist note)".
  - The plist carries only the SIGTERM comment. The note with the path,
    System Settings → General → Language & Region → Translation Languages, is
    in the plan's prose (`task-10-wiring.md:304-306`). Someone setting up a
    new machine does not read the plan.
  - **Scenario.** On a fresh install the model is missing, so every Enter
    shows an error. The message sends the user to a file that does not have
    the fix.
  - The line is byte-identical to the plan. Putting the path in the message
    fixes it.

### Deviations from the plan
- **Schema change 4 now covers `full_shape`.** The header item 4, the comment
  above `full_shape`, `decisions.md:505-510` and `smoke-report.md:100-105`
  explain it. It is the user's choice, and an improvement.
- **`install.sh`.** `put`'s exits (`:19-31`) and the warn-and-continue for
  launchd (`:74-94`) are explained in the script's comments and in
  `smoke-report.md:106-110`. They are improvements; yellow 1 is the gap they
  leave.
- **`rime/ime_translate.yaml`.** `-w` is last, and the focus-change line is
  added. Both are explained in the author's response and in
  `smoke-report.md:111-113`. They are improvements.
- **The processor's log line** (:100) is round 1's green. It adds no other
  change.
- Everything else is as in round 1.

### What was walked
- **Dimension 1.** The `commit_text` calls are at :106 and :113, and the
  clears at :108 and :115. The re-show branch (:98-102) now logs as well. It
  still neither commits nor clears. `install.sh` never touches a live draft.
- **Dimension 2.** The engine lists are unchanged. The built schema has one
  Lua component, and it comes first.
- **Dimension 3.** `decide.lua:46-54` and the processor's :53-63 are
  unchanged.
- **Dimension 4.** No module state was added. `log` reads `S.settings`.
- **Dimension 5.** There is no new shell string in Lua. `install.sh`'s
  quoting held again, with every sandbox `HOME` containing a space.
- **Dimension 6.** Three mutants of the guard ran on a scratch copy. The
  unmodified copy passes 81.
  - guard removed: fails #77, "commits nothing unseen"
  - guard returning kNoop: fails #76, "enter after the prompt vanished is
    taken"
  - guard without `show`: fails #78, "the translation is shown again"
- **Dimension 7.** `config.load` on the shipped `ime_translate.yaml` gives 0
  warnings, with these values:
  - `libretranslate` at `http://127.0.0.1:8989`
  - 1500 and 2000
  - `debug_log` false, `allow_remote` false
  - `api_key_account` empty
- **Dimension 8.**
  - The processor's comment rests on row 22, now labelled observed by the
    agent and accepted.
  - The `full_shape` comment rests on round 1's source reading (F14 and
    `switcher/save_options`).
  - §5.1's anchor is green 1.
- **Dimension 9.** Nothing that v1 excludes. The report's mixed-script
  section adds no code.
  - `Shift_R: commit_text` is confirmed in the built `default.yaml:18`, a
    config reading, as labelled.
  - Left Shift is labelled unverified.
- **Installer sandbox**, with `HOME` redirected and `launchctl` and Squirrel
  stubbed:
  - **Runs 1 and 2.** Run 2 printed only `redeployed` and the closing text.
    The tree hashed the same, 13 files.
  - **B, C, E and F** are above.
  - **Run 5.**
    - A foreign `default.custom.yaml` and a user `ime_translate.yaml` were left
      untouched, and the merge hint printed.
    - A `rime.lua` with no trailing newline got the binding on its own line.
- **Live machine, read-only.**
  - **Installed files.** All eight Lua files, the schema,
    `default.custom.yaml` and the plist are `cmp`-identical to the repo. The
    processor was installed at 18:34.
  - **Deploy and processes.**
    - The 18:34:42 deploy logged 10 success, 0 failure. Its only warning is
      `grammar.yaml`.
    - Squirrel has run since 18:35:19.
    - `translate --serve` has run with PPID 1 since 08:43.
  - **Debug log.** It was last written at 17:08, and `debug_log` is off. The
    new "off screen" line has not appeared yet, as expected.
  - **`user.yaml`** holds only `previously_selected_schema:
    luna_pinyin_translate`, which is D6's case.
- **Commands.**
  - `scripts/run_tests.sh`: 9 PASS (backend 126, config 75, decide 60,
    glue_load ok, decode 88, encode 10, processor 81, session 36, state 17).
  - `.githooks/pre-commit`: exit 0.
  - `git status --porcelain=v2` was identical before and after the tests,
    the hook and the sandbox runs. The only change I made is this entry.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every smoke check in Step 6 passes: gate rows as specified, record rows once written down | **not met** | Every gate row passes except row 21. Rows 4, 5, 22, 23 and 27 pass on agent observation that the user accepted (`decisions.md:494`). Row 17 passes on a posted keycode (gate "if possible"). The record rows are written down. Row 21's specified trigger, the wheel, was never performed, and no recorded decision lets Task 10 close without it (red 1) |
| install.sh is idempotent and never overwrites user config | ok | Sandbox runs 1-2 and 5. The failure paths are yellow 1 |
| install.sh preserves the `ime_translate/` subdirectory | ok | Sandbox and live: `lua/ime_translate/` holds the 6 modules |
| `rime/ime_translate.yaml` contains no secret, only `api_key_account` | ok | `config.load`: `api_key_account` empty, 0 warnings. The Keychain instruction now prompts for the key |

### Verdict
1 red / 2 yellow / 4 green: the task **cannot** be marked done.

The code carries no red. No path eats text, and nothing new commits. The red is
row 21 alone, and it needs the user: either one trackpad gesture or one
recorded sentence.

### Author's response (Task 10, round 2)

- **Red: closed by measurement at the user's instruction.** The user wrote "You
  can do the test by yourself", so the agent ran row 21 as planned: a wheel,
  then Esc.
  - A single line-unit wheel event did not page Squirrel's window. A posted
    trackpad-like gesture did: continuous pixel deltas, phases
    began/changed/ended, from `cgev.py swipe`.
  - With the prompt showing in state B, the highlight moved from `不过` to
    `不谷` while the old prompt stayed on screen. That is §6.2's residual, now
    seen.
  - Esc kept the draft `今天bu guo` and dropped the prompt.
  - The row is labelled "agent, at the user's instruction". decisions.md's
    Task 10 entry now names row 21 alongside the five accepted rows, so the two
    documents agree.
- **Yellow 1: fixed.**
  - The restart notice moved into an `EXIT` trap, so any exit after new Lua is
    in place prints it.
  - The plist step reports a failed copy and goes on, as its comment says.
  - The final `cat` notice was removed, so it does not print twice.
  - Sandbox re-runs, with `HOME` redirected and `launchctl`/Squirrel stubbed:
    - normal, twice: exit 0, and the second run installs nothing
    - read-only schema target: `FAILED to install …`, then the notice, exit 1
    - `LaunchAgents` not writable: `FAILED to install … plist`, then
      `redeployed`, `Install complete` and the notice, exit 1
    - bootstrap failing: `FAILED to start`, then `redeployed` and the notice,
      exit 1
- **Yellow 2: fixed.** `tests/test_processor.lua:256` now says "observed by
  the agent".
- **Greens:**
  - **F16** is added to upstream.md (`switcher.cc`, `fix_schema_list_order`),
    and §5.1 cites it.
  - **D6's cell** says "to the vendor".
  - **The installed config** was replaced with the new template, as the user
    agreed. The two differed only in comments.
  - **install.sh's model note** gives the System Settings path instead of
    "see the plist note".
- **Also recorded:** left Shift's inline English, now reproduced with a
  one-process tap. It holds only as the draft's tail. Tapping back re-reads the
  English as pinyin (`请你整理一个热爱多么文件`). This is the basis for the
  user's request to redesign mixed input, which is not part of Task 10.

---

## Task 10: Schema wiring + installer + smoke — round 3

Range: `34b7e09..HEAD` is still empty, because Task 10 is uncommitted. The index
was reviewed as `git diff --cached` (15 files). Its hash did not change during
the round. **The working tree did.** At 19:23:47 local time, while this round
was running, four files gained unstaged changes: the schema's processor order,
architecture.md §4.1 and §5.2, decisions.md, and smoke-report.md ("Shift+Enter
switched the IME to English"). They are Task 10's deliverables, so they are
reviewed here as the current state. **The red is in them. The index alone
carries none.** `progress.json` is ledger state and was not reviewed.
Time: 2026-09-22T02:47Z

Evidence labels as in round 1. No machine was driven. Read this round:
- the index and the working tree
- librime `gear/ascii_composer.cc` at tags 1.16.0 and 1.17.0 (identical apart
  from the header), and master commit `74bd5dc` (2026-09-18)
- librime 1.16.0 `engine.cc`, `gear/editor.cc`, `rime_api_impl.h` and
  `switcher.cc`
- Squirrel master `SquirrelInputController.swift` and `SquirrelPanel.swift`
- `~/Library/Rime/` and its `build/`
- Rime's own INFO logs (deploy times only)
- the agent's row-21 and Left Shift screenshots in the scratch directory
- `~/Library/Logs/ime_translate.log`: its mtime, nothing else

### Round 2, finding by finding
| Round 2 | Status | Evidence |
|---|---|---|
| 🔴 row 21's wheel never run, and no recorded decision | closed | The user's instruction is recorded (`decisions.md:500-503`). Row 21 (`smoke-report.md:89`) says what was done and by whom ("agent, at the user's instruction"), and no longer says "pending" or "accepted". The agent's screenshots show it. Before the gesture: page 1 with `不过` highlighted and `-> Today is just` showing. After it: page 2 (`不谷` … `不觚`) with the same prompt. The prompt staying tells the branches apart, because a key would have voided the phase and taken the prompt with it. Source reading at Squirrel master: `SquirrelPanel.sendEvent` handles `.scrollWheel` in the panel and calls `SquirrelInputController.page(up:)`, which calls `rimeAPI.change_page`. librime 1.16.0 `RimeChangePage` only calls `Context::Highlight`, so no key event is sent. A mouse wheel, whose events carry no phase, reaches the same call once its deltas add up past 10. So the gesture stands in for the plan's mouse wheel, and one line-unit event not paging is expected (derivation). Row 21 is observed by the agent, not measured, as decisions.md and the report both say. The round-2 author response's "closed by measurement" is the one place that says otherwise |
| 🟡 1 the restart notice skipped on an early exit | closed | Sandbox runs B2, C1, D1 and F1 (What was walked): every exit after new Lua prints the notice, and a failed plist copy warns and goes on |
| 🟡 2 the test comment says "measured" | closed | `tests/test_processor.lua:256` says "observed by the agent" |
| 🟢 the anchor for §5.1's correction | closed | F16 (`upstream.md:58`), with its symbols checked at 1.16.0 `switcher.cc:165-180` and `:290`. §5.1 cites it |
| 🟢 D6's cell | closed | `decisions.md:23` says "to the vendor" |
| 🟢 the installed config's old command | closed | `~/Library/Rime/ime_translate.yaml` is `cmp`-identical to the template. It was replaced at 19:05:25 |
| 🟢 install.sh's model note | closed | `install.sh:129-130` gives the System Settings path |

### 🔴 Must fix
- **`rime/luna_pinyin_translate.schema.yaml:48-50` (working tree): with
  `ascii_composer` ahead of the processor, a draft's Enter can be rejected to
  the application before the processor sees it.** This reopens R15's measured
  text loss, which Task 8 fixed only inside `decide`.
  - **The chain**, source reading at 1.16.0 unless marked:
    1. A draft, then a Left Shift tap and English letters. This is the inline
       English tail the smoke report observed (`请你整理一个readme`; agent).
    2. Caps Lock.
       - Squirrel forwards it (`SquirrelInputController.handle`,
         `.flagsChanged`). Row 26 saw it reach librime.
       - In `AsciiComposer::ProcessCapsLock`, three conditions hold:
         `good_old_caps_lock` is on (built `default.yaml:11`),
         `toggle_with_caps_` is false (the Shift toggle set it,
         `ToggleAsciiModeWithKey`), and `ascii_mode` is on.
       - So the press returns kRejected without calling `SwitchAsciiMode`.
         `Caps_Lock: clear` does not clear, and the draft stays open with Caps
         Lock on.
    3. Enter. It carries `kLockMask`; spike R15 measured `mod=0x2`.
       `ProcessKeyEvent` calls `ProcessCapsLock` before anything else. With
       `good_old_caps_lock` on, `key_event.caps()` makes every key that is not
       a letter return kRejected, and `ConcreteEngine::ProcessKey` stops there.
    4. The processor never runs. Spike R15 measured what follows a rejected
       Enter with a draft open: "whose newline replaced the marked text. The
       draft was lost and Enter was delivered" (`spike-report.md:248-252`).
  - **With the processor first, as staged**, it takes that Enter: `decide`
    drops Lock (Task 8), and the draft translates. So the reorder brings the
    loss back. `risks.md:146`, "which is now safe", no longer holds.
  - **Scenario.**
    1. In WeChat, the user types a sentence, taps Left Shift and types `api`.
    2. Caps Lock gets pressed, by mistake or to capitalise and then thought
       better of.
    3. The next key is Enter, to translate.
    4. The newline replaces the draft, and WeChat's Enter sends. That is the
       spike's "a send with the message eaten". Nothing on screen warns of it.
  - **Not run on the machine.** Steps 2 and 3 are source readings. Step 4 is
    the spike's measurement, made with a synthetic flag. To settle it, run this
    in TextEdit, never WeChat:
    - a draft, a one-process Left Shift tap, then `readme`
    - Caps Lock, as a flagsChanged event (as row 26)
    - Return carrying the Caps Lock flag

    Pass: the draft is still there. The spike once saw a synthetic Caps Lock
    Return switch the input source to ABC (`spike-report.md:446-448`).
  - **The same state, in both orders.** Every letter typed after step 2 is
    rejected the same way, because the processor passes letters on anyway.
    That half is not new. It sits with R15's open second path and belongs to
    `/design-review`, not to this red. What the reorder adds is Enter, the one
    key §6.2 promises always meets check 2 ("every Enter passes this check
    first", `architecture.md:294`).
  - **What else rests on the reorder.** These support the red; they are not
    separate findings.
    - **§5.2's claim.** `architecture.md:190-196` says the processor "still
      sees Enter before the native chain". Step 3 is a counterexample, and no
      F-row says what `ascii_composer` takes ahead of it.
      - At 1.16.0 and 1.17.0 it takes: `Caps_Lock`; every key carrying the Lock
        bit (`ProcessCapsLock`); `Eisu_toggle`; printable keys in `ascii_mode`
        while composing (`PushInput`); and every key in `ascii_mode` with
        nothing composing. Otherwise Return and Escape pass.
      - Keys it takes never reach `decide`. So §5.2's "everything else: void
        first" (`:170`) and §6.2's check 1 do not cover them.
      - Check 2 catches the ones that change the draft, at the next key the
        processor sees (derivation).
    - **Upstream has moved further.** librime master `74bd5dc` (2026-09-18,
      after the 1.17.0 release) adds a step to
      `AsciiComposer::ProcessKeyEvent`.
      - In `ascii_mode` while composing, Return or space with no modifier runs
        `CommitAndReset(ctx->input())`: it commits the raw input and clears.
      - Behind that code, on a Squirrel release that carries it, Enter on an
        inline-English draft commits the raw pinyin and English untranslated,
        and the processor never sees it.
      - That is a second commit exit in front of the only one §3.1 allows.
        With the processor first, it does not arise.
    - **No recorded choice.** `decisions.md:531` applies the order "as a
      defect fix within Task 10". The row-22 and full-width entries say the
      user chose them; this one does not, and it changes a line of design §4.1.
  - **To clear.** This is the user's call. Record it in decisions.md, with an
    F-row for `ascii_composer` naming the symbols above. Two options, both by
    derivation and unverified:
    - **Keep the processor first, and fix Shift+Enter another way.** For
      example, the processor also takes the Shift release that follows a
      Shift+Enter it accepted, so `ascii_composer` never sees a lone release.
      The cost, from `ProcessKeyEvent`: a lone Shift tap straight after, with no
      other key in between, does not toggle.
    - **Keep the reorder, remove the rejecting path, and record the master
      change as a risk.** For example, `Caps_Lock: noop` skips
      `ProcessCapsLock` entirely, and also closes R15's second path. That is a
      `/design-review` item. Then re-run row 11 and the Esc rows (10, 21, 28) on
      the new order.

### 🟡 Should fix
1. **`docs/smoke-report.md:169-171`: the Right Shift line is a derivation
   labelled as a config reading, and source reading points the other way.**
   - The config reading covers only `Shift_R: commit_text` (built
     `default.yaml:18`).
   - "It would commit the Chinese draft untranslated" does not follow for this
     schema.
     - `AsciiComposer::SwitchAsciiMode` with `commit_text` calls only
       `Context::ConfirmCurrentSelection()`.
     - `ConcreteEngine::OnSelect` commits only when `_auto_commit` is set, and
       `FluidEditor` sets it false (`editor.cc:43`, `:189`). That is this
       schema's change 1.
     - So the selection is confirmed, nothing commits, and `ascii_mode` goes on
       with no reset, because the update connection is made only for
       `inline_ascii`. Letters then join the draft through `PushInput`.
     - This is a derivation from 1.16.0 source, unverified. The line's
       behaviour does hold for `express_editor` schemas such as
       `luna_pinyin_simp`.
   - **Scenario.** The user asked for a mixed-input redesign on the strength of
     this section.
     - This line rules Right Shift out ("not a way to mix") and leads to "needs
       a design change" (`:167-168`).
     - By source reading, Right Shift may already confirm the Chinese typed so
       far and let English go on in the same draft. That is the case Left Shift
       loses.
     - `:167-168` also sits oddly against `:150-153`, where a capital-first
       word in mid-sentence already works.
   - **Fix.** Label the line a derivation. One posted Right Shift tap, sent the
     way the Left Shift one was, settles it.
2. **`docs/smoke-report.md` no longer agrees with itself, or with the shipped
   schema, after the reorder.**
   - `:46` says the processor "comes first among the processors". The
     working-tree schema and the built one
     (`build/luna_pinyin_translate.schema.yaml:29-30`) put `ascii_composer`
     first.
   - Row 11 (`:79`) says **pass**, while `:130-132` says "This is a limit of
     row 11 as run, not a pass". Row 18 (`:86`) sent Shift+Enter the same way,
     and nothing mentions it.
   - The deviation list (`:199-211`) leaves out the move. It departs from the
     plan's "comes first" (`task-10-wiring.md:59`, `:98-99`).
   - All 28 rows ran with the processor first, and the report does not say
     which of them carry over to the new order, or why. The re-run covered
     Shift+Enter, Enter Enter and a lone Shift tap. It did not cover the Esc
     rows or row 26.
   - **Scenario.**
     - `/task-done` reads the table and finds row 11 passed, while the report's
       own prose calls it "not a pass".
     - Task 11, chasing a key the processor never saw, trusts `:46`.
   - **Fix, once the red is settled:**
     - Record row 11's re-run in its row.
     - List the move under deviations.
     - Say which rows were re-run on the shipped order; the rest carry over by
       source reading.
     - Update `:46`.

### 🟢 Suggestions
- **`smoke-report.md:14-15` says "`debug_log` was on, and every row's log lines
  were checked".**
  - That is not so for the full-width re-run, row 21's gesture, the Left Shift
    runs or the Shift+Enter re-run. The log was last written at 17:08:30. The
    installed config has had `debug_log` off since then, and was replaced by
    the template at 19:05:25.
  - Two more gaps nearby: `:16-18` dates the acceptance of every 👁 row to
    round 1, and the legend (`:21-24`) has no entry for "at the user's
    instruction".
  - **Scenario.** Someone auditing row 21 looks for log lines that were never
    written.
  - One qualifying line fixes both.
- **Row 21 is not cited where the design needs it.**
  - §6.2's Residual (`architecture.md:302-305`) and §6.4's list (`:357`) do
    not cite row 21. It is now the one observation of that residual: a stale
    prompt beside a page-2 highlight.
  - The no-key path (Squirrel `page(up:)`, then `RimeChangePage`, then
    `Context::Highlight`) has no F-row, yet the Esc rule at processor :56-62
    rests on it.
  - **Scenario.** A `/design-review` of §6.2 plans a measurement that has
    already been made.
- **`scripts/install.sh:19-27`: after a FAILED line, the notice still says to
  restart now.**
  - **Sandbox I1**, with a read-only installed `session.lua`:
    - Four modules are new, and `session.lua` is old.
    - `state.lua` and the processor are not copied, and `rime.lua` is not
      bound.
    - There is no `--reload`.
    - Then the run prints "Lua changed … run: … --quit".
  - Following the notice loads a partial set. The notice cannot simply be
    dropped on failure, because the rerun after the fix prints none (round 2's
    point).
  - **Scenario.** A pull changes `decide.lua` and `session.lua` together. The
    user restarts Squirrel on the notice before fixing the ownership, and the
    new `decide` runs against the old `session`.
  - **Suggestion.** When the exit status is not 0, word the notice as "fix the
    FAILED step and rerun; this notice will not repeat, so restart after that
    clean run".

### Deviations from the plan
- **The processor's position (working tree).** decisions.md :516-541 and
  smoke-report.md :122-144 explain it as a defect fix. It is the red.
- **`install.sh`'s `EXIT` trap and the plist step's warn-and-continue.** The
  script explains them (:16-18, :90-92). They are improvements.
- Everything else is as in round 2.

### What was walked
- **Dimension 1.**
  - The `commit_text` calls are at :106 and :113, and the clears at :108 and
    :115. The processor has not changed since round 2 (mtime 18:33:14).
  - `ascii_composer`'s own `ctx->Clear()`, for Caps Lock and Eisu (`clear`),
    now runs before the processor. The outcome is the same as before (row 26).
  - The phase left behind is caught by check 2. Any path back to a non-empty
    draft passes through the processor first, while the draft is still empty
    (derivation).
  - The reorder's Enter path is the red.
- **Dimension 2.**
  - At 1.16.0, `ascii_composer` commits ahead of the processor only through
    `engine_->CommitText`, for a letter that carries the Lock bit while
    `good_old_caps_lock` is off. It is on here, so there is no such commit.
  - Master `74bd5dc` is the red.
- **Dimension 3.**
  - Check 1 is skipped for the keys `ascii_composer` takes (the red).
  - Check 2 catches those that change the draft (derivation):
    - `PushInput` recomposes, and `Segmentation::AddSegment` replaces the last
      segment, so its prompt goes.
    - `Clear` removes the composition.
- **Dimension 4.** No module state was added.
- **Dimension 5.** There is no new shell string in Lua. `install.sh`'s quoting
  held in every sandbox, each with a `HOME` containing a space.
- **Dimension 6.**
  - `test_processor` passes 81. The processor is unchanged since round 2's
    mutants, so they were not re-run.
  - The reorder has no test, and cannot have one headless. The fake engine
    hands every key to the processor, which is the very assumption the red is
    about.
- **Dimension 7.** The config has not changed since round 2.
- **Dimension 8.** F16 checks out against its source. The red is the gap.
- **Dimension 9.** Nothing that v1 excludes.
- **The Left Shift paragraph** (`smoke-report.md:158-168`), as the caller
  asked: honestly labelled.
  - It says observed by the agent, says the tap was posted, and keeps the
    failed two-process tap.
  - The agent's screenshots show `请你整理一个热爱多么文件` as a draft, then
    translated.
  - The two-process failure fits `ProcessKeyEvent`'s 500 ms toggle window
    (derivation).
  - "So inline English holds only as the draft's tail" is a fair inference from
    those runs.
  - Right Shift is yellow 1.
- **Installer sandbox.** A copy of `install.sh` had `SQUIRREL` and `TRANSLATE`
  pointed at stubs, with `launchctl` stubbed on `PATH` and `HOME` redirected to
  a path containing a space.
  - **A1, twice.**
    - Run 1 installed the 8 Lua files, bound `rime.lua`, and installed the
      schema, `default.custom.yaml`, the config and the plist. It started the
      service, printed the notice after "Install complete", and exited 0.
    - Run 2 printed only `redeployed` and the closing text, and exited 0. The
      tree (13 files) hashed the same.
  - **B2, a read-only installed schema.** `FAILED to install …schema.yaml`,
    then the notice, exit 1. There was no `--reload`, and the old content
    stayed.
  - **C1, a `LaunchAgents` at mode 555.**
    - The plist step printed FAILED, and the run went on: `redeployed`,
      "Install complete", the notice, exit 1.
    - After the permissions were fixed, a rerun installed the plist, started
      the service and exited 0, with no notice (the Lua was identical). The
      failing run had already shown it.
  - **D1, bootstrap failing with 5.** `FAILED to start`, `redeployed`, the
    notice, exit 1.
  - **F1, `--reload` failing.** The notice, exit 3.
  - **I1, a read-only `session.lua`.** Green 3.
  - **E1, user files present.** A foreign `default.custom.yaml` and a user
    config were left untouched, and the merge hint printed. A `rime.lua` with
    no trailing newline got the binding on its own line.
  - The trap keeps the exit status (0, 1 and 3 above).
- **Live machine, read-only.**
  - The 8 Lua files, `default.custom.yaml` and the plist are `cmp`-identical to
    the repo. The config is identical to the template.
  - **The installed schema is not the repo's right now.**
    - Rime's logs show deploys at 19:20:45, 19:23:47 (`install.sh`, per the
      backup stamp), 19:26:59 and 19:28:53. Squirrel restarted at 19:27:27,
      19:29:26 and 19:31:07.
    - The 19:23:47 backup holds the reordered processors under the old header
      comment.
    - The installed schema now also carries `lua_processor@spike_mix_proc`,
      ahead of the processor, and `lua_translator@spike_mix_tr`, both marked
      "THROWAWAY spike". `rime.lua` lines 2-4 bind them, and
      `lua/spike_mix.lua` exists.
    - None of this is Task 10's diff, and none of it was reviewed.
      `install.sh` restores the schema (keeping a backup) but not `rime.lua`
      or `spike_mix.lua`.
  - The Shift+Enter re-run fits the 19:20:45–19:23:47 window: the reordered
    schema, without the spike (derivation from the backup and the deploy
    times).
- **Commands.**
  - `scripts/run_tests.sh`: exit 0, 9 PASS (backend 126, config 75, decide 60,
    glue_load ok, decode 88, encode 10, processor 81, session 36, state 17).
  - `.githooks/pre-commit`: exit 0. It checks staged content only. The four
    working-tree files passed `checks_language` when run by hand.
  - `git status --porcelain=v2` was identical before and after the tests, the
    hook and the sandbox runs, against a snapshot taken after the working tree
    moved. The index hash did not change all round. The only change I made is
    this entry.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every smoke check in Step 6 passes: gate rows as specified, record rows once written down | **not met** | Row 21 now passes, which closes round 2's red. With the staged schema every gate row passes. But the shipped schema, the working tree, is not the one the rows ran on, and on it a draft's Enter can reach the application (red). Row 11's status also contradicts itself (yellow 2) |
| install.sh is idempotent and never overwrites user config | ok | Sandbox A1 and E1. Failure paths: B2, C1, D1, F1 and I1 |
| install.sh preserves the `ime_translate/` subdirectory | ok | Sandbox A1, and the live machine |
| `rime/ime_translate.yaml` contains no secret, only `api_key_account` | ok | Unchanged since round 2 |

### Verdict
1 red / 2 yellow / 3 green: the task **cannot** be marked done.

Round 2's findings are all closed, and the staged index carries no red. The red
arrived with the working-tree reorder during this round. On it, draft → Left
Shift → Caps Lock → Enter reaches the application, and a measured R15 loss
returns. Where the processor sits is the user's call. If it goes back to first,
the red goes, and Shift+Enter needs another fix. Before `/task-done`, the live
install should match the repo again.

### Author's response (Task 10, round 3)

- **Red: fixed as the user chose.**
  - The processor goes back first, and `ascii_composer`'s `Shift_L`/`Shift_R`
    are `noop` in the translation schema (schema change 8). The whole
    `switch_key` map and `good_old_caps_lock: true` are spelled out, because a
    schema-level map replaces default.yaml's.
  - The built schema shows both the order and the map. The installed files equal
    the repo, and the spike components are gone:
    - `rime.lua` holds only the processor binding
    - `lua/` holds no `spike_mix.lua`
    - the built schema has no `spike_mix` component (the word "spike" remains
      only in comments)
  - Recorded in architecture.md §4.1 and §5.2, and in the decisions.md
    Shift+Enter entry, where the first fix is marked withdrawn and your round-3
    red is summarised with `74bd5dc`. The smoke report and the deviation list
    are updated too.
  - **Verification is incomplete, and it is recorded so.**
    - The Enter, Enter loop re-ran fine.
    - The agent's posted Shift events had become unreliable. A delivery check
      failed: a Shift press posted while a prompt showed left the prompt in
      place.
    - The Shift+Enter re-run therefore proves nothing about Shift. It is pending
      the user's physical keyboard.
- **Yellow 1: fixed.** The Right Shift sentence is corrected: `commit_text` is
  `ConfirmCurrentSelection`, which under `fluid_editor` does not commit. It is
  labelled a derivation, and it is moot under change 8. The left-Shift paragraph
  says it describes the stock config before change 8.
- **Yellow 2: fixed.**
  - Line 46 now names the final order.
  - Rows 11 and 18 are noted as unable to show a Shift toggle; row 11's pass
    stands for the commit only.
  - The deviation list gains change 8 and the withdrawn intermediate order.
  - The re-runs under each order are stated.
- **Greens:**
  - **The debug_log sentence** now gives 17:08:30 and says which rows were
    checked by readback only.
  - **F17** is added to upstream.md (scroll → `page(up:)` → `RimeChangePage` →
    `Context::Highlight`, no key event). §6.2's residual cites F17 and row 21.
  - **install.sh's EXIT notice** now tells the user to fix the error and re-run
    before restarting when the exit is non-zero.
- **Harness note** (smoke report): posted flagsChanged events stopped reaching
  Squirrel around 19:28. Posting every modifier as released brought them back
  once; they then failed again. The cause is not found.

---

## Task 10: Schema wiring + installer + smoke — round 4

Range: `34b7e09..HEAD` is still empty, because Task 10 is uncommitted. The index
was reviewed as `git diff --cached` (15 files). The working tree equals the
index, and the index tree (`8638a64`) did not change during the round. The
Shift check the coordinator ran during this round (A and B below) is not in the
files yet. It is judged in yellow 1 and under acceptance.
Time: 2026-09-22T03:28Z

Evidence labels as in round 1. No machine was driven. Read this round:
- the index
- librime 1.16.0: `gear/ascii_composer.cc` in full; `engine.cc`
  `InitializeComponents` and `OnOptionUpdate`; `switcher.cc`
  `ProcessKeyEvent`; `rime_api_impl.h` `RimeChangePage`
- librime master `ascii_composer.cc` (round 3's copy), for `CommitAndReset`
- Squirrel master `SquirrelPanel.swift` `sendEvent`
- `~/Library/Rime/`, its `build/` and its schema backups
- Rime's own INFO log for the running Squirrel: timestamps and option and
  property names only (it logs no values)
- the coordinator's `vA` and `vB` screenshots, and the harness's `cgev.py`, in
  the scratch directory
- `~/Library/Logs/ime_translate.log`: its mtime (17:08:30, unchanged), nothing
  else

### Round 3, finding by finding
| Round 3 | Status | Evidence |
|---|---|---|
| 🔴 behind `ascii_composer`, a draft's Enter can be rejected before the processor sees it | closed | The processor is first again (schema `:52`; built `:38`). `Shift_L` and `Shift_R` are `noop` (`:161-162`; built `:24-25`). The rest of the map equals built `default.yaml:11-16`. The chain needed two things, and both are gone. (1) `ascii_mode` switched on by Shift with a draft open: `noop` stores no binding (`load_bindings`, `ascii_composer.cc:40-41`), so the release toggles nothing (`ToggleAsciiModeWithKey` :226-228). (2) An Enter rejected by `ProcessCapsLock` ahead of the processor: the processor now meets it first, and `decide.lua:16,28` drops Lock. Change 8 adds no path; see What was walked |
| 🟡 1 the Right Shift line | closed | `smoke-report.md:194-198` labels it a derivation, names `ConfirmCurrentSelection`, and calls it moot under change 8 |
| 🟡 2 the report disagrees with itself | closed; one residual (green 4) | `:46-49` names the final order. The deviations (`:230-233`) list change 8 and the withdrawn order. The re-runs under each order are stated (`:141-161`), and `:163-165` limits row 11's pass to the commit. The 18:34 backup is the smoke-run schema. It differs from the final one only in `full_shape`, change 8 and comments, so rows 1-28 ran on the order that ships |
| 🟢 the debug_log sentence | closed in part (green 4) | `:14-16` gives 17:08:30 |
| 🟢 row 21 and the no-key path | closed | F17 (`upstream.md:59`) checks out (green 5 has two nits). §6.2's residual cites F17 and row 21 (`architecture.md:311-316`) |
| 🟢 install.sh after a FAILED line | closed for its case (green 3) | Sandbox I1 below |
| The live install should match the repo | done | What was walked |

### 🔴 Must fix
None. The red-line walk is under What was walked.

### 🟡 Should fix
1. **The new Shift check settles change 8 only in part. A cannot fail, and B
   needs one control.** It is not in the files yet. It is due at
   `docs/smoke-report.md:154-161` and `docs/design/decisions.md:557-560`, which
   say "pending the user's physical keyboard" today.
   - **What produces the defect** (1.16.0, `ascii_composer.cc`): a Shift
     release toggles only when three things hold. `ascii_composer` saw the
     press, it saw no other key in between, and the release comes within
     500 ms (:88-101, :113-116). So a check shows the defect only if the release
     reaches Rime inside that window.
   - **A cannot tell the fix from the defect.**
     - The press was posted alone and read back before the Return. The release
       was posted after the Return.
     - `cgev.py` posts one event per process for a modifier (`mod`), so the
       press and the release came from different processes.
     - That is the form of the report's own "two-process tap". Under the stock
       config it did not toggle (`smoke-report.md:184-185`).
     - An AppleScript readback inside the 500 ms window also spends most of it,
       and the run did not record the interval.
     - So A would have shown "stays Chinese" on the defective config as well.
       The defect was reproduced only by a one-process sequence (`:129-131`).
   - **B can tell them apart, if its release arrived.**
     - The tap was one process, 60 ms apart. That form did toggle under the
       stock config (`:183-184`).
     - The prompt vanishing proves the press arrived. Nothing proves the
       release did. Under change 8 a release that arrives has no visible
       effect.
     - The harness has lost posted flagsChanged events since 19:28, cause
       unknown (`:167-169`). The 19:55 probe lost a press.
   - The screenshots agree with the report. `vA`: the Chinese committed, then
     `n` as pinyin with five candidates. `vB`: `好的n` in the preedit, with
     candidates. Rime's INFO log has no `updated option: ascii_mode` between the
     engine start at 20:13:58 and 20:21:42 (`engine.cc` `OnOptionUpdate` logs
     every option change). So nothing toggled. Whether the release arrived, the
     log cannot say.
   - **Scenario.** The report records change 8 as verified on A and B. B's
     release had been dropped, as the 19:55 probe's press was. Change 8 was then
     never exercised, and the record cannot tell. A later edit that loses the
     `noop` would pass the same check.
   - **Fix, in one sitting, in this order:**
     1. The control. `Ctrl+Shift+T` into `luna_pinyin_simp`, open a draft, one
        one-process tap. The draft turns English (`n` stays literal), and Rime's
        INFO log gains `updated option: ascii_mode`. Tap back, then
        `Ctrl+Shift+T` back. This shows that the poster's releases land now.
     2. B, as run.
     3. A, run as the one-process `shifted` sequence that reproduced the defect,
        with no readback inside it. Then `n` should be pinyin.

     Record all three as "agent, at the user's instruction". If step 1 does not
     toggle, this harness cannot carry the check, and it needs the user's
     keyboard: one Shift+Enter then `n`, and one lone Shift tap then `n`.
2. **There is no F-row for `ascii_composer`, and change 8 leans on three of its
   behaviours** (dimension 8; round 3's "To clear" asked for one).
   - **Where.**
     - `architecture.md:190-201` says "source reading" with no anchor.
     - `decisions.md:524-527`.
     - The schema's `:152-153`: "a schema-level map replaces default.yaml's".
   - **Checked at 1.16.0, and all of them hold:**
     - `noop` stores no binding (`load_bindings` :40-41).
     - A release with no binding toggles nothing (`ToggleAsciiModeWithKey`
       :226-228).
     - A schema's `switch_key` map replaces the preset's, while
       `good_old_caps_lock` falls back to the preset on its own (`LoadConfig`
       :196-212).
     - The order also rests on the tap rule (`ProcessKeyEvent` :88-122) and on
       the Lock rejection (`ProcessCapsLock` :151-156, :171-184).
   - **Scenario.** The map-replace rule is what keeps Caps Lock stock here.
     1. Someone trims change 8 to the two Shift lines, reading the maps as
        merged.
     2. `bindings_` then holds no `Caps_Lock`, and `caps_lock_switch_style_`
        stays noop (:190, :213-222).
     3. `ProcessCapsLock` never runs (:68). A key carrying Lock goes on to the
        speller instead of being rejected.
     4. R15's second path changes shape silently, and no row catches it.
   - **Fix.** Add an F18 naming these symbols at 1.16.0, and cite it from §5.2
     and from the schema comment.
3. **The design cites a feature and a section that the repository does not
   have.**
   - `architecture.md:203-205` has "(§5.5 in 002's design)" and "Feature 002
     gives the Shift tap back". The same promise is at schema `:19-20` and at
     `decisions.md:555-556`.
   - `architecture.md` §5 ends at §5.4. `docs/features/` holds only 001, and no
     decision opens 002. The text exists only as a draft outside the repository
     (the agent's scratch `design-002-draft.md`).
   - **Scenario.**
     - A `/design-review` follows the citation to check "inline_ascii held
       English only as the draft's tail", and finds nothing. The evidence is
       `smoke-report.md:183-192`.
     - The cost of change 8 reads as scheduled and temporary, while nothing in
       the repository schedules it.
   - **Fix.** Cite the smoke report's "Mixed Chinese and English" section for
     the claim. Say that feature 002 is proposed, or open it, with its decisions
     entry, before citing it.

### 🟢 Suggestions
1. **The stated cost of change 8 leaves out the fallbacks that destroy the
   draft.**
   - `decisions.md:555-556` and `architecture.md:203` say only that Shift
     switches nothing.
   - Here is what is left for English in the middle of a draft:
     - Caps Lock clears the draft: row 26, `ascii_composer.cc:163` and
       :262-265.
     - `Ctrl+Shift+T` drops it (§5.1).
     - Only a word with a capital first letter keeps it
       (`smoke-report.md:175-182`).
   - **Scenario.** The user taps Shift and nothing happens. They reach for Caps
     Lock, Squirrel's other stock switch, and lose the sentence.
   - One sentence in the cost fixes it, pointing at row 26's `/design-review`
     candidate.
2. **`decisions.md:516`'s heading still announces the withdrawn fix** ("the
   processor moves behind `ascii_composer`").
   - **Scenario.** Someone scanning the headings for the processor order reads
     the withdrawn decision.
3. **`install.sh`'s notice after a non-zero exit (sandbox).** Round 3's I1 case
   is fixed. Two gaps remain:
   - **C1, a `LaunchAgents` at mode 555, and the other `status=1` paths.**
     - The output says "Install complete", then that "the install did not
       finish". Stderr says "the IME is installed, the local backend is not".
     - The IME is complete. A cloud-backend user has no reason to fix the
       LaunchAgent. They are told not to restart Squirrel, and nothing later
       tells them to.
   - **B2, then a rerun after the fix.**
     - The rerun exits 0 and prints no restart line, because the Lua has not
       changed since the failed run.
     - So in that sequence the `--quit` command and the focus-change caveat
       never appear.
   - **Suggestion.**
     - Set a `finished=1` flag just before `exit "$status"`, and let the trap
       pick its wording from it.
     - In the fatal branch, say that the rerun will not repeat the notice, and
       print the restart command there.
4. **The smoke report's opening, legend and row 11.**
   - `:15-16`, "Rows re-run after that, from row 21 on", reads as rows 21-28.
     Only row 21 was re-run after 17:08:30. Row 22's re-run had log lines
     (decisions.md, "Task 10 smoke").
   - `:17-19` dates every acceptance to round 1. Row 21's came after round 2.
   - The legend (`:22-25`) still has no "at the user's instruction". Row 21
     uses it, and A and B will.
   - Row 11's cell (`:82`) has no pointer to `:163-165`. Round 3 asked to
     record row 11's re-run in its row; A and B are that re-run.
   - **Scenario.** An auditor who reads only the table.
5. **Two nits in F17** (`upstream.md:22`, `:59`).
   - `:22` scopes tag 1.16.0 to F13–F16. F17's librime half therefore reads as
     master, though round 3 read `RimeChangePage` at 1.16.0.
   - F17's symbols name only `.scrollWheel`. Its claim also covers the
     page-arrow click, which is `.leftMouseUp` (`SquirrelPanel.swift:80-86`,
     master).
   - Checked: both paths call `page(up:)`, and `RimeChangePage` only highlights
     (`rime_api_impl.h:1007-1028`).
6. **Putting the processor first shields only the Enter half of `74bd5dc`**
   (`decisions.md:550-551`).
   - A space in ascii mode while composing still passes the processor and
     reaches `ascii_composer`. On that code it runs
     `CommitAndReset(ctx->input() + " ")`, which commits the raw input.
   - Change 8 removes the Shift way into that state. The switcher menu's
     `西文` remains. It cannot happen on 1.16.0.
   - **Suggestion.** Add a line saying that a Squirrel upgrade past librime
     1.17.0 triggers a `/design-review`.

### Verification status, as asked
- **What the staged files say is exact.**
  - `smoke-report.md:156-161` says Shift is not verified, that a delivery check
    failed, and that the check is pending the user's physical keyboard.
  - `decisions.md:557-560` says the same.
  - Neither calls the Shift+Enter re-run a pass.
- **Acceptance cannot close on "pending". It needs the check first.**
  - To the letter, item 1 is met. Every row ran on the processor order that
    ships, and row 11's spec (the commit, and no `translate` line) passed.
  - But change 8 was applied after the run, to fix a defect in row 11's own
    key. Closing on "pending" would ship a schema change that nobody has seen
    work. Task 10 is marked `manual` precisely because its behaviour has to be
    observed.
  - The check does not have to be the user's own keypress. The user asked for
    this run ("can you do it by yourself?"). By row 21's precedent (decisions.md,
    "Task 10 review, round 1"), it counts once it is written down with that
    label, provided it can tell the fix from the defect: yellow 1's control, and
    A re-run in one-process form. Otherwise it needs the user's keyboard.

### Deviations from the plan
- **Schema change 8.** It is explained, with the user's decision
  (`smoke-report.md:230-233`, `decisions.md:552-556`). It is a fix, not an
  omission.
- **The processor's position** is the plan's again.
- **`install.sh`'s trap wording.** It is explained (:16-18), and it is an
  improvement (green 3).
- Everything else is as in round 3.

### What was walked
- **Scope.**
  - What changed since round 3: the schema (the order restored, change 8),
    architecture.md §4.1, §5.2 and §6.2, decisions.md, upstream.md (F17),
    smoke-report.md, and `install.sh`'s trap (:19-31, diffed against round 3's
    copy).
  - The processor and its test are unchanged since round 2 (mtime 18:33:14).
  - The config template, `default.custom.yaml` and the plist are unchanged
    since round 3 (`cmp`).
- **Dimension 1.**
  - The processor's commit/clear pairs are at :106-108 and :113-115.
  - Change 8 adds no clear and no commit.
    - With `noop`, a Shift release reaches `ToggleAsciiModeWithKey` (:96). It
      returns at :227-228, before `SwitchAsciiMode`.
    - `SwitchAsciiMode` is the only place where a switch key calls `Clear`,
      `Commit` or `ConfirmCurrentSelection` (:257-265).
    - So two paths go (`inline_ascii`; `commit_text` →
      `ConfirmCurrentSelection`), and none arrives.
  - Caps Lock keeps `clear` (:163, :262-264). That is row 26, unchanged.
    - Change 8 affects only its rejecting branch (:151-156), the one that keeps
      the draft. That branch needs `ascii_mode` on with `toggle_with_caps_`
      false.
    - Shift can no longer produce that state. Only the switcher menu can.
  - On the switcher route, Enter still meets the processor first, and Lock is
    dropped.
  - Letters carrying Lock are still rejected (:171-184). That is R15's second
    path, as before.
- **Dimension 2.** On 1.16.0, `ascii_composer` commits only at :179, and only
  while `good_old_caps_lock` is off. It is on (schema `:155`, built `:18`). For
  master, see green 6.
- **Dimension 3.**
  - "First" means first among the schema's processors. The switcher sits ahead
    of all of them (`engine.cc:336-337`).
  - It takes its hotkeys, and every key while its menu is open
    (`switcher.cc:51-71`). The menu is on screen, and nothing there changed this
    round.
  - Every other key meets check 2 and `decide`.
- **Dimension 4.** No Lua changed.
- **Dimension 5.** No shell string in Lua changed. `install.sh`'s quoting held
  in every sandbox, with a `HOME` containing a space.
- **Dimension 6.**
  - `test_processor` passes 81, unchanged. Round 2's mutants stand.
  - Change 8 has no headless test, and cannot have one: the fake engine has no
    `ascii_composer`. The manual check is yellow 1.
- **Dimension 7.** The config is unchanged.
- **Dimension 8.** F17 checks out. The missing `ascii_composer` row is yellow 2.
- **Dimension 9.** Nothing that v1 excludes.
- **Live machine, read-only.**
  - **Files.**
    - These are `cmp`-identical to the repo: the 8 Lua files,
      `default.custom.yaml`, the config and the plist.
    - `rime.lua` is one line, the processor binding.
    - `lua/` holds only `ime_translate/`, the processor and
      `ime_translate_shared.lua`. There is no `spike_mix.lua`.
  - **The schema.**
    - The installed schema is `cmp`-identical to the repo (19:58:35).
    - The built schema's `__build_info` timestamp for it matches that mtime
      (1790045915).
    - The built schema has one Lua component, the processor, first (:38). Its
      `ascii_composer` map is at :17-25.
    - Neither the build nor `rime.lua` contains the string `spike`.
  - **Leftovers.** The four `.bak-*` copies do not end in `.schema.yaml`, and
    `build/` holds no schema built from them.
  - **Squirrel.** Its current process started at 19:59:26, after that deploy.
    So A and B ran on this build.
- **Installer sandbox.**
  - **Setup.** A copy of `install.sh` had `SQUIRREL` and `TRANSLATE` pointed at
    stubs, with `launchctl` stubbed on `PATH` and `HOME` pointed at a path
    containing a space.
  - **A1, twice.**
    - Run 1 installed everything. The restart notice came after "Install
      complete", and the run exited 0.
    - Run 2 printed only `redeployed` and the closing text, and exited 0. The
      tree hashed the same after both runs.
  - **The Rime directory read-only.** `mkdir` failed before any Lua was copied.
    There was no notice, and the run exited 1.
  - **B2, a read-only installed schema.**
    - The Lua and the binding were new. The run printed `FAILED to install …`,
      then the fatal notice, and exited 1.
    - After the permission was fixed, the rerun exited 0 with no restart line
      (green 3).
  - **C1, `LaunchAgents` at mode 555.** Green 3 shows its output. It exited 1.
  - **F1, `--reload` failing.** The fatal notice, with nothing printed above it
    by the stub, and exit 3.
  - **I1, a read-only `session.lua`.** Four modules were new. The fatal notice
    appeared, and the run exited 1.
- **Commands.**
  - `scripts/run_tests.sh`: exit 0, 9 PASS (backend 126, config 75, decide 60,
    glue_load ok, decode 88, encode 10, processor 81, session 36, state 17).
  - `.githooks/pre-commit`: exit 0. It saw staged Lua and ran the unit tests.
  - `git status --porcelain=v2` was identical before and after the tests, the
    hook and the sandbox runs.
  - `git write-tree` gave `8638a64` before and after. It writes only a tree
    object. The working tree still equals the index.
  - The only change I made to the repository is this entry.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every smoke check in Step 6 passes: gate rows as specified, record rows once written down | **pending the Shift check** | Every row ran on the processor order that ships. Row 11's spec (the commit) passed. Change 8, applied after the run, has no observation yet that could have failed (yellow 1). This closes once that check is recorded |
| install.sh is idempotent and never overwrites user config | ok | Sandbox A1. The user-file branches did not change since round 3 (E1 there) |
| install.sh preserves the `ime_translate/` subdirectory | ok | Sandbox A1, and the live machine |
| `rime/ime_translate.yaml` contains no secret, only `api_key_account` | ok | Unchanged since round 3 (`cmp`) |

### Verdict
0 red / 3 yellow / 6 green: no red. The task is **not yet** clear to close,
because acceptance item 1 waits on the Shift check.

Round 3's red is closed. The processor is first again, and change 8 removes
Shift's two switch paths without adding one. The staged record states the
Shift verification exactly as it stands: pending. The new agent run can close
it once yellow 1's control shows that the posted release lands, and A is
re-run in one-process form. Both then need recording with their label.
Otherwise the user presses the two keys.

### Author's response (Task 10, round 4)

- **Yellow 1 (the Shift check): settled by the user.** The agent's attempts
  could not discriminate:
  - The control in `luna_pinyin_simp` did not toggle, twice, once with a
    modifier-release sweep after the `Ctrl+Shift+T` chord. So the agent's
    posted taps cannot be trusted as delivered.

  The user then checked on the physical keyboard, in the translation schema:
  1. After Shift+Enter, pinyin shows the candidate window: Chinese.
  2. After a lone Shift tap, it is still Chinese.

  This is recorded as *measured* (the user) in the smoke report and in
  decisions.md. Acceptance item 1's last open point rests on it.
- **Yellow 2: fixed.** F18 is added to upstream.md
  (`AsciiComposer::LoadConfig` / `load_bindings` / `ProcessKeyEvent` /
  `ToggleAsciiModeWithKey` / `ProcessCapsLock` at 1.16.0), covering:
  - a schema-level map replacing the default one, `good_old_caps_lock` included
  - a `noop` style storing no binding
  - a release with no binding toggling nothing
  - the 500 ms tap rule
  - the reject path

  architecture.md §5.2 cites it. The version line reads F13–F18.
- **Yellow 3: fixed.** The citation of "§5.5 in 002's design" is gone.
  architecture.md, the schema comment and decisions.md now say feature 002 was
  designed with the user and is not yet in this repository; the smoke report
  is cited for the tail-only behaviour of `inline_ascii`.
- **Greens:**
  1. **The stated cost** now names Caps Lock (`clear`) and `Ctrl+Shift+T` as
     the remaining ways into English with a draft open, and says that both
     discard the draft.
  2. **The decisions.md heading** now reads "Shift now switches nothing in the
     translation schema".
  3. **install.sh:**
     - "Install complete." only on status 0; otherwise "Install finished with
       errors".
     - A failed run after new Lua leaves `.ime_translate_restart_pending`, so
       the next successful run still prints the restart notice and then removes
       the marker.
     - Sandbox, `LaunchAgents` unwritable, then fixed, then once more: exit 1
       with the marker, then exit 0 with the notice and no marker, then exit 0
       with no notice.
  4. **Smoke report:**
     - The debug_log sentence lists the later runs.
     - Row 21's later acceptance is stated.
     - The legend gains "agent, at the user's instruction", and makes plain
       that only "user" is measured.
     - Row 11's cell points to the Shift section.
  5. **F17** names `.leftMouseUp` on a page arrow, and its version scope is
     covered by the F13–F18 line.
  6. **`74bd5dc`'s space half** is noted in decisions.md: it is unreachable on
     1.16.0 with Shift `noop`, and Caps Lock clears first.

---

## Task 11: README + compatibility matrix + translate evaluation — round 1

Range: `823df7c..HEAD` is empty, because Task 11 is uncommitted. The index was
reviewed as `git diff --cached 823df7c`: 7 files, +417/−6. The working tree
equals the index.
Time: 2026-09-22T08:16Z

No machine was driven and nothing was typed into any application. Read this
round:
- the index, the plan `task-11-eval.md`, and in decisions.md "001 Task 11
  revised before start" and D4
- design §5.1, §5.2, §5.5, §8.2 and §10.4; spike S7 and S8; 001 smoke rows
  27–28; 002's smoke report, and rows 22 and 45 of its plan
- what the README describes:
  - `config.lua` DEFAULTS, `backend.lua`, `ime_translate_shared.lua` (the
    Keychain lookup), the processor's `log`, and `decide.lua`'s Enter and
    Space branches
  - `rime/ime_translate.yaml`, `rime/default.custom.yaml`, the schema,
    `install.sh` and the plist
- the installed copy. Every Lua file, the schema and `rime.lua` match the
  repository. Squirrel's deployed `app_options` for Terminal were read too.
- the agent's scratch evidence:
  - `results.txt`, `drive.sh`, `chord.py` and `term-out.txt`
  - the TextEdit, Chrome and Safari C1 screenshots, viewed
  - `wechat-title.png`: its pixel size only, not opened
- `eval/results-translate.md`, the ignored artifact, compared with the
  appendix cell by cell

Run:
- `.githooks/pre-commit` over the index (language, secrets, gate): exit 0
- `scripts/run_tests.sh`: 10 files, exit 0
- `bash -n scripts/eval.sh` and `git diff --cached --check`
- a copy of `eval.sh`, in the scratch directory, against a fake `/translate`
  server and against a dead port
- the uninstall's `rm` line under zsh, with no backups present

Red lines, dimensions 1–5: the diff touches no Lua, schema or install script,
so there is no path to walk. Dimension 8: see green 6.

### 🔴 Must fix
1. **Acceptance item 1 is not met: eight matrix cells hold a value, not a
   verdict.**
   - **Where.** `docs/compat-matrix.md:42-45`, columns C6 and C7, for
     TextEdit, Chrome, Safari and the Safari address bar.
   - **What they hold.** "`jintian` (raw pinyin)", "`jin tian` (the preedit,
     with its spaces)", "`jintian`" and "Chinese". None of them is
     supported, needs config or unverified.
   - **Why.** The check table gives C6 and C7 no criterion to judge by:
     `:35-36` reads "What lands in the field (D2)" and "Chinese, or English by
     `app_options`". The C5 cells did get a verdict ("supported: inline, …"),
     and so did Terminal's C7 ("needs config"). The rule was applied to some
     cells and not to others.
   - **Scenario.** `/task-done` checks acceptance item 1 against the matrix,
     and eight cells fail its wording. Nothing in the matrix says whether
     Chrome's `jin tian`, which differs from the raw keys, counts as
     supported.
   - **Fix.**
     - Give C6 and C7 a "Supported when" criterion. For example, C6: what
       lands is the raw input as D2 documents, and nothing else is lost. C7:
       the field starts in Chinese.
     - Then prefix the eight cells, as in `supported: jintian (raw pinyin,
       D2)` or `supported: Chinese`.
     - Whether Chrome's spaced preedit passes C6 is the user's call. Its cell
       should say which.

### 🟡 Should fix
1. **The Notes run: the matrix described an automation step in a private
   application too softly.** The finding asked for the order of events, and
   for the user to be told how to check. Details are left out of the
   published record.
2. **The observation method says screenshots were "never of a private
   application", but WeChat was captured.**
   - **Where.** `docs/compat-matrix.md:11-12`.
   - **The evidence.** The capture file is 2184×128 px:
     the full width of WeChat's window, 64 pt high. The matrix's own `:54-56`
     implies a narrow capture was taken ("without a wider screenshot").
   - The plan allowed checking the chat's title, so the capture may be
     acceptable. The sentence is still false.
   - **Scenario.** The user confirms the matrix on the strength of "never of a
     private application". Meanwhile a strip of WeChat's top edge, which can
     show the open chat's name, is still on disk in the session scratch
     directory. So is `clip.bak`, the user's saved clipboard.
   - **Fix.**
     - Say what was captured: a strip of WeChat's title, taken to check which
       chat was open, and nothing else.
     - Tell the user that both scratch files exist. Deleting them is the
       user's call.
3. **The key table tells a first-time user that Enter translates pinyin. In
   fact Enter keeps it as letters.**
   - **Where.** `README.md:49` reads "Enter | With a draft | translate".
   - **What the code does.** Per design §5.2 (idle Enter) and `decide.lua:41`,
     Enter with unselected pinyin is `lock_literal`. It translates only once
     nothing is left unselected.
   - `README.md:57-58` says so, but further down, under the Mixed heading.
   - **Scenario.**
     1. A new user types `nihao` and presses Enter, as the table says.
     2. The draft becomes the letters `nihao`.
     3. The next Enter commits `nihao` as is, since the draft has no Chinese
        (`decide.lua:43`).
     4. The pinyin lands in the chat box instead of a translation.
   - **Fix.** Either change the Enter cell, or say at the top of the section
     to select the Chinese (Space or a number) and then press Enter. The cell
     could read: "pinyin left unselected: kept as letters (see Mixed);
     everything selected: translate".
4. **The README never says that `Ctrl+Shift+T` throws away an open draft.**
   - **Where.** `README.md:40-42`.
   - **The design.** Switching schemas "clears draft and state" (§5.1). §5.2
     lists it among the ways a draft is discarded.
   - **Known limits** (`:124-137`) covers focus loss, which at least commits
     the raw pinyin. It leaves this one out, and this one commits nothing.
   - **Scenario.** A user types a long sentence, decides to send it in
     Chinese, and presses `Ctrl+Shift+T` to go back to plain pinyin. The whole
     draft disappears. Shift+Enter would have committed it.
   - **Fix.** One sentence under Switching schemas: switch with no draft
     open, and to keep a draft as Chinese, press Shift+Enter first.
5. **The uninstall block removes too little under zsh, and too much when it
   is pasted whole.** `README.md:141-153`.
   - **The glob.** `:144` puts the schema and its `.bak-*` backups on one
     `rm` line.
     - The user's login shell is zsh with `nomatch` on (checked with
       `zsh -ic`). With no backups present, zsh refuses the whole line with
       "no matches found". `rm` exits 1 and the schema stays. This was
       reproduced in a scratch directory.
     - Backups exist only after a re-install that changed the schema. So a
       machine installed once hits this. So does this machine, on a second
       uninstall after a reinstall.
     - **Scenario.** The schema stays in `~/Library/Rime` with its Lua gone.
       If `default.custom.yaml` still lists it, the schema is still
       selectable. That can happen two ways: the step at `:145` is manual,
       and a `default.custom.yaml` the user merged by hand is never
       mentioned. The schema's `lua_processor` then has no binding. The spike
       found such a component "created with no error and never runs" — a
       derivation for this state.
   - **The settings file.** `:147` runs whenever the block is pasted, despite
     its comment "if you want them gone". The optional Keychain line, `:152`,
     is commented out.
     - **Scenario.** A user uninstalls in order to reinstall, and loses a
       custom `prompt` and `api_key_account`.
   - **Fix.**
     - Put the backups on their own line, in a form that tolerates no match:
       `find "$R" -maxdepth 1 -name 'luna_pinyin_translate.schema.yaml.bak-*' -delete`.
     - Comment out `:147`, as `:152` is.
     - Add one line for a `default.custom.yaml` merged by hand: remove the
       `luna_pinyin_translate` entry and the `Control+Shift+T` binding from
       it.
6. **`eval.sh` reports a latency for a run that failed, and exits 0.**
   - **Where.** `scripts/eval.sh:30-35,45-46`. A failed request still adds
     its time to `times`, and neither the summary line nor the exit status
     changes.
   - **Reproduced.** A copy of the script, pointed at a dead port, wrote 30
     rows of `ERROR URLError`, then `wrote …: 30 sentences, P50 0 ms, P95 0
     ms`, and exited 0.
   - The plan's code does the same. The judged run has no ERROR row, so the
     numbers on record stand.
   - **Scenario.** The README (`:160`) invites a rerun. The service is down,
     or the proxy problem is back. The person running it reads "P50 0 ms" as
     a faster backend.
   - **Fix.**
     - Keep failed requests out of `times`, count them in the summary line,
       and exit non-zero if there were any.
     - Optionally, mark any row over 1500 ms, the IME's `timeout_ms`. The
       eval waits up to 10 s, but in the IME such a request is
       `✗ 翻译超时`.
7. **The record hides that 18 of the 30 sentences were composed, and §2
   misnames the score.**
   - The user's decision (decisions.md, "001 Task 11 revised before start")
     says the 18 composed sentences are "marked as not from real chat".
     Nothing marks them:
     - `eval/sentences.txt` has no note. `eval.sh` skips `#` lines, so a
       comment line would do.
     - `docs/compat-matrix.md:91-128` does not say it.
     - testing.md §10.4 still says "30 real chat sentences from the user".
   - The new §2 row (`requirements.md:29`) says "21 of 30 chat sentences
     acceptable". But "chat" is one of the five categories, and it scored
     7 of 8.
   - Plan Step 4 asked for the share by category in §2. The row gives only
     the total.
   - **Scenario.** A later backend comparison reads §2, not the appendix. It
     takes 21/30 as `translate`'s quality on the user's real chat. In fact
     chat scored 7/8 and URLs 1/5, and the agent wrote 18 of the 30
     sentences.
   - **Fix.**
     - Mark the 18 in `sentences.txt`, and say so in the eval section.
     - In §2, write "21 of 30 eval sentences (chat 7/8, code 5/6, url 1/5,
       emoji 3/5, mixed 5/6)".
     - Add one line under §10.4's D4 note.
8. **Plan deviations that no sentence explains.**
   - **The rows.** Step 2 gives Slack, Notion, Gmail, "iMessage as a
     conversation" and VS Code "one row each".
     - The matrix has one merged row (`compat-matrix.md:51`).
     - It has no row for an iMessage conversation. The Messages row, a new
       message with no recipient, is a different case: in a conversation,
       Enter sends.
   - **The §2 file.** The plan names `docs/design/architecture.md` §2, in its
     Files list and in Step 5's `git add`. But §2 lives in `requirements.md`.
     The implementation edits the right file. Step 5's command, run as
     written, would not stage it.
   - **Scenario.** A reader checking the matrix against the plan cannot tell
     whether the iMessage row was dropped on purpose.
   - **Fix.** One sentence for each, in the matrix and in the decisions.md
     entry.

### 🟢 Suggestions
1. **`temperature` is missing from the config table** (`README.md:78-89`).
   `config.lua:22` accepts it, with a default of 0.2, and the openai adapter
   sends it (`backend.lua:51`). A user of a local openai-compatible model who
   wants steadier output cannot find the key.
2. **The key table has no error state.** After `✗ …`, Enter commits the
   Chinese draft (§5.2; `decide.lua:39`). A user who presses Enter again to
   retry gets Chinese in the box.
3. **"0.5–2 s" per Enter** (`README.md:95-96`) goes past the cap. The freeze
   is capped at `timeout_ms`, 1.5 s by default, so a 1.8 s cloud reply
   becomes `✗ 翻译超时`. §8.2 allows raising it to 4000 for cloud, and the
   cloud example (`:106-113`) does not mention that.
4. **The uninstall leaves `~/Library/Logs/ime_translate.log`,** which the
   README's own note (`:120-122`) says holds what was typed. Add an `rm -f`
   line for it.
5. **Apps that start in English go unmentioned.** Squirrel's stock
   `app_options` start Terminal, iTerm2, VS Code, Xcode and others in
   `ascii_mode` (F24). The README says nothing about it; the matrix's
   Terminal note covers one of them.
6. **`docs/compat-matrix.md` wording:**
   - **`:96`, "exactly as the IME's libretranslate adapter sends them".** The
     JSON value is the same, but the bytes differ. `json.dumps` sends
     `\uXXXX` escapes (seen at the fake server); `json.escape` sends raw
     UTF-8. `ensure_ascii=False` would make them the same.
   - **`:47`, Terminal C5, "a source reading" with no anchor.** Spike S7
     observed exactly this, a floating preedit under stock `no_inline: true`
     (`spike-report.md:49,428`). Cite it.
   - **`:74`, "drop `com.apple.Terminal` from `app_options`".** A Rime patch
     cannot delete a key. Dropping it would also drop `no_inline`, leaving an
     inline preedit in Terminal, which is untested. Give the patch line that
     sets `ascii_mode: false` alone.
   - **`:21-24`, "no Enter was left to the application".** Terminal received
     every Enter: `term-out.txt` holds the newlines, since the run was in
     English. And "In WeChat, the IME took both Enters" refers to 001 row 27,
     not to this run, which typed nothing into WeChat.
7. **The appendix drops the bar the verdicts used.**
   `eval/results-translate.md` defines "acceptable" as "the meaning is kept
   and the sentence is usable in chat". That is what explains row 29, and
   `compat-matrix.md:130-165` does not carry it.
8. **The URL-protection idea (`:123-126`) exists only in prose.** Neither
   `progress.sh decisions` nor risks.md will ever surface it. If it is meant
   to happen, it needs a row or an `/issue`.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every matrix cell is one of supported / needs config / unverified; none blank | **not met** | None is blank. Eight C6/C7 cells hold a value without a verdict (red 1). The user's confirmation of the matrix is also pending |
| The 30-sentence set covers chat, code identifiers, URLs, emoji and mixed Chinese-English | ok | 8 chat, 6 code, 5 url, 5 emoji, 6 mixed. Identical line for line to the plan's listing (compared by script) |
| translate evaluated on the 30 sentences: each judged (agent first, user confirms), P50/P95 recorded | agent's part ok; **the user's pending** | Every row has a verdict. P50 20 ms and P95 37 ms, recomputed by nearest rank from the appendix's ms column. Per-category counts, recomputed from the verdict column: 7/8, 5/6, 1/5, 3/5, 5/6, total 21/30. The appendix equals `eval/results-translate.md` in source, translation and ms on all 30 rows. `compat-matrix.md:128`: not yet confirmed by the user |
| The eval's conclusion on the default backend is written into compat-matrix.md and design §2 | ok; wording, yellow 7 | `compat-matrix.md:123-126`; `requirements.md:29`, where §2 lives |

Also checked, with no finding:
- **The README against the code.**
  - The other config defaults and meanings match `config.lua` DEFAULTS and
    `ime_translate.yaml`.
  - The Keychain command: service `ime-translate`, and `-w` last, as
    `ime_translate_shared.lua:17` reads it.
  - The log note matches the processor's `log`, which at `:129` writes the
    draft and the translation.
  - Shift+Enter, Esc, Space, the Shift tap, Caps Lock `noop` and BackSpace
    match §5.2, §5.5 and `decide.lua`.
  - D2, D6 and R13 are stated as the ledgers state them.
- **The uninstall's `sed` on `rime.lua`** deletes exactly the line that
  `install.sh:76-81` writes. The schema binds only `ime_translate_processor`.
- **`eval.sh` against `backend.lua:65-75`.**
  - The fake server saw the path `/translate` and
    `Content-Type: application/json`, and the keys `q`, `source: zh`,
    `target: en` and `format: text`.
  - The proxy bypass is the only change from the plan's code. It is explained
    in the script and at `compat-matrix.md:96-98`. It matches the IME's
    `--noproxy '*'` for loopback (`backend.lua:141-144`): an improvement.
  - Pipes in a cell are escaped (`T\|…`).
- **The matrix cells against the raw notes and the screenshots.**
  - TextEdit, Chrome, Safari and the address bar, C1–C4 and C6: as
    `results.txt` records them.
  - C5: the screenshots show the draft inline, with
    ` -> I'm a little tired today.` after it.
  - The WeChat cells cite 001 rows 27–28 and 002 row 45, and those rows say
    what the cells claim. Plan row 45 is the Enter way in File Transfer,
    confirmed "user, overall".
  - Terminal's `^@` is in `term-out.txt`.
- **Language.** The pre-commit check passes on all 7 staged files. The
  Chinese in the `.md` files is in backticks.

### Verdict
1 red / 8 yellow — the task **cannot** be marked done

### Author response to round 1
- **Red 1, fixed.** C6 and C7 now have a "Supported when":
  - C6: what was typed lands raw, and nothing is lost. That is D2's
    documented cost, and the cell records what landed.
  - C7: a new field starts in Chinese. It is "needs config" when
    `app_options` start it in English.

  The eight cells for TextEdit, Chrome, Safari and the Safari address bar now
  read "supported: …". Chrome's `jin tian` is marked supported, with "the user
  may judge otherwise", and it is raised with the user.
- **Yellow 1, addressed.** The Notes finding now states the order of events
  and how the user can check. The user had already been told, and chose to
  continue. The agent reads nothing in Notes.
- **Yellow 2, fixed.** The screenshot sentence now names the one exception, a
  thin strip across the top of WeChat's chat pane. That file and `clip.bak`
  are deleted from the agent's scratch directory, and the user is told.
- **Yellow 3, fixed.** The README's Enter row and the "Translating" paragraph
  say that Enter translates only with everything selected, and that
  `nihao` ⏎ ⏎ commits `nihao`.
- **Yellow 4, fixed.** The README says switching schemas with a draft open
  discards it.
- **Yellow 5, fixed.**
  - The uninstall block deletes backups with `find … -delete`, which zsh runs
    with no backup present (checked).
  - The settings file, `default.custom.yaml` with the hand-merged entries, and
    the Keychain item are listed as the user's own choices, not in the pasted
    block.
  - The marker is "first line starts with", matching the actual first line.
- **Yellow 6, fixed.** A failed request is no latency sample. The summary
  gives the failure count and prints no percentile when every request failed,
  and the script exits 1 on any failure. Checked: port 9 gives "30 failed",
  and exit 1.
- **Yellow 7, fixed.**
  - `eval/sentences.txt` opens with comment lines marking the 18 composed
    sentences; `eval.sh` skips `#` lines.
  - testing.md §10.4 gains a note on the set as run.
  - The §2 row now gives the per-category scores, and says "21 of 30
    sentences", not "chat sentences".
- **Yellow 8, fixed.**
  - The uninstalled applications have one row each, the iMessage conversation
    included.
  - A deviation from the plan: design §2 lives in `requirements.md`, not
    `architecture.md` as the plan's Files list says, and the row was edited
    there.
- **New while fixing.** Two later `eval.sh` runs gave P50 45–49 ms and P95
  127–149 ms, higher than the judged run's 20/37. The matrix and the §2 row
  now say that latency varies with load, still far inside 800 ms.
- **Recorded in the conclusion.** The user decided to stay with `translate`,
  and to move to a local LLM only if a need appears.

---

## Task 11: README + compatibility matrix + translate evaluation — round 2

Range: `823df7c..HEAD` is still empty, because Task 11 is staged, not
committed. It was reviewed as `git diff --cached 823df7c`: 9 files, +829/−6,
the review log included. `git diff` was empty before this entry, so the index
and the working tree were the same. Round 1's versions of the matrix, the
README and `eval.sh` were recovered as dangling blobs (`f3c21ec`, `d193e90`,
`9be5680`) and diffed against the index, so every change since round 1 was
read as a change. `progress.json` is ledger state and was not reviewed.
Time: 2026-09-22T08:43Z

No machine was driven and nothing was typed into any application. Read this
round:
- the index; the plan `task-11-eval.md`; decisions.md, "001 Task 11 revised
  before start" and the new "the eval results stay an artifact"; `.gitignore`'s
  history (`eval/results-*.md` since `c8d02a1`)
- `decide.lua` (the Enter branches), `install.sh` (the backup names, the
  marker, the `default.custom.yaml` branch), `rime/default.custom.yaml`, and
  `backend.lua`'s openai adapter headers
- the agent's scratch directory: its listing and the raw results
- the current `eval/results-translate.md`, the ignored artifact

Run:
- `.githooks/pre-commit` over the index: exit 0. `scripts/run_tests.sh`: 10
  PASS, exit 0. `git diff --cached --check` and `bash -n scripts/eval.sh`:
  clean.
- the matrix's 14 rows × 7 cells, by script: all 98 begin with supported, needs
  config or unverified
- the appendix against `eval/sentences.txt` (category and source, row by row)
  and against the current artifact (translations, all 30 rows), by script
- a copy of the staged `eval.sh`, in the scratch directory, against an
  in-process fake `/translate` (one HTTP 500, one reply starting with
  `ERROR `) and against port 9
- the uninstall's `rm -f` and `find … -delete` lines, as a zsh script with
  `nomatch` set, with and without backups present; and the user's interactive
  zsh options (`interactivecomments` on, `nomatch` on)

Red lines, dimensions 1–5: the diff still touches no Lua, schema or install
script, so there is no path to walk.

### Round 1, finding by finding
| Round 1 | Status | Evidence |
|---|---|---|
| 🔴 1 eight C6/C7 cells hold a value, not a verdict | closed | C6 and C7 have a "Supported when" (`compat-matrix.md:39-40`). The eight cells at `:46-49` read `supported: …`, and the scripted check finds 98 of 98 cells starting with a verdict. Chrome's `jin tian` is flagged for the user's call (see the acceptance table) |
| 🟡 1 the Notes finding | closed | The order of events and the user's check are stated |
| 🟡 2 "never of a private application" | closed | `:11-16` names the exception. The scratch listing has no `wechat-title.png` and no `clip.bak`. The text says "the top of WeChat's chat pane", while round 1 read the pixel width as the whole window's; with the file gone that can no longer be checked, and no exposure remains |
| 🟡 3 the Enter row | closed | `README.md:45-48` and `:52` match `decide.lua`: unselected → `lock_literal`, then a draft with no Chinese → `commit_draft`, so `nihao` ⏎ ⏎ commits `nihao` as written |
| 🟡 4 a schema switch discards the draft | closed | `README.md:43` |
| 🟡 5 the uninstall block | closed | Under zsh with `nomatch`, `rm -f` and `find … -delete` both exit 0 with no backup present; with two backups present, both go and an unrelated file stays. The pattern matches `install.sh:53`'s `.bak-$STAMP`. The settings file and the Keychain item are out of the pasted block; the hand-merged `default.custom.yaml` has its line; "first line starts with" matches `rime/default.custom.yaml:1` and `install.sh:92`. The trailing `# backups, if any` is safe to paste only because this user's zsh has `interactivecomments` on (checked). One residual, green 4 |
| 🟡 6 `eval.sh` failure handling | closed | Fake server: the HTTP 500 row is `ERROR HTTPError`, the summary says "2 failed" (the second is green 1), the percentiles are over the successes, exit 1. Port 9: "30 failed", exit 1. The three `#` lines are skipped: 30 rows from 33 lines |
| 🟡 7 composed sentences unmarked; §2 misnames the score | partly closed | `eval/sentences.txt:1-3` marks the 18; testing.md §10.4 has the note (`:112-118`); the §2 row gives the five category scores and says "sentences". The eval section of the matrix still does not say it: yellow 2 |
| 🟡 8 plan deviations | closed | One row each at `compat-matrix.md:55-59`, the iMessage conversation included. The §2-in-`requirements.md` deviation is explained in the author's response above, which is this project's record of deviations; the matrix and decisions.md do not repeat it, and need not |
| 🟢 1–8 | 7 now weightier (green 2); the rest not taken | Advisory. 1–6 and 8 stand as round 1 wrote them |

Also checked, with no finding:
- **The new decisions.md entry.** `.gitignore` has ignored `eval/results-*.md`
  since the harness commit, as it says. Dropping the deliverable leaves
  acceptance item 3 unaffected: the appendix is the record.
- **The latency note.** The current artifact is one of the "later runs": P50
  45 ms, P95 149 ms. Its 30 translations are identical to the appendix's, so
  the runs differ in time only. The §2 row's "up to P95 about 150 ms" matches.
- **The conclusion.** `:141-148` records the user's decision to keep
  `translate`, and the §2 row says "The default stands". The Ollama route
  through the `openai` adapter is plausible as written: the adapter sends
  `Authorization` only when there is a key (`backend.lua:42`, a source
  reading of this project's own code; not tried).

### 🔴 Must fix
None.

### 🟡 Should fix
1. **The C1 criterion dropped the plan's "nothing sent or run". Nothing says
   why.**
   - **Where.** `compat-matrix.md:34` reads "The English commits; no Chinese
     residue". The plan's C1 (`task-11-eval.md:91`) ends "; nothing sent or
     run". Unchanged since round 1, which missed it.
   - **What covers it now.** Only `:25-28`, "Where the Enter keys went", and
     that is about this run: WeChat (from 001 row 27) and Terminal.
   - **Why it matters.** This clause is the only check in the matrix for
     "send is always manual" (CLAUDE.md), and no hook checks that red line.
     `README.md:56-57` tells the user it holds "in a chat app". It has been
     observed in WeChat only.
   - **Scenario.**
     1. Someone fills in the Slack row, or the iMessage conversation, later.
        Seven rows are all unverified, waiting for that.
     2. In C1, the Enter that commits the English also reaches the app, and
        the message is sent.
     3. Judged by `:34`, the English committed with no Chinese residue, so the
        cell reads "supported". The plan's criterion would have failed it.
   - **Fix.** Put "nothing sent or run" back in C1's "Supported when", or
     say in one sentence why it was dropped. In `README.md:57`, add "(observed
     in WeChat; see the matrix)".
2. **The eval section still does not say that 18 of the 30 sentences were
   composed.** This is what is left of round-1 yellow 7.
   - **Where.** `compat-matrix.md:107-150`. The provenance is in
     `eval/sentences.txt:1-3` and in testing.md §10.4 (`:114-116`) only.
   - **What changed the reach.** The §2 row (`requirements.md:29`) used to
     point at testing.md §10.4. It now points only at `compat-matrix.md`, and
     so does `README.md:140`. A reader following either link reaches the
     results, and never the note.
   - **Scenario.** The conclusion (`:146-148`) anticipates a local LLM "if a
     need appears". Whoever weighs that reads the matrix and takes 21/30 as
     `translate`'s quality on the user's own sentences. In fact rows 13–30 were
     written by the agent: 3 of the 8 chat rows and all 6 mixed rows.
   - **Fix.** One sentence in the eval section, as round 1 asked: 12 from the
     plan, 18 composed by the agent (rows 13–30), not from real chat.

### 🟢 Suggestions
1. **`eval.sh:34` tells a failure from a translation by the text `ERROR `.**
   A real translation that starts with it counts as failed. In the fake-server
   run, a 200 reply `ERROR 404 IS THE ROUTE` for row 17 was counted in
   "2 failed", dropped from the percentiles, and made the script exit 1.
   `translate` has already produced a sentence in capitals (row 29), so a
   source like `错误 404` could do this. Set a flag in the `except` branch
   instead. Also, when every request fails, the summary prints
   `P50 None ms` rather than no percentile, as the author's response says:
   cosmetic.
2. **Round-1 green 7 is now weightier: the only written bar for "acceptable" is
   in this log.** The two later runs overwrote `eval/results-translate.md`.
   The current file has an empty verdict column and no definition. The bar
   ("the meaning is kept and the sentence is usable in chat") now survives only
   in round 1's quote. That bar is what separates row 21 (acceptable) from row
   22 (not), and the user is about to confirm verdicts judged by it. One line
   above the appendix.
3. **The latency figures do not agree across files.** `README.md:138` says "a
   P50 of about 20 ms", and testing.md §10.4 (`:117`) gives only 20/37. Two of
   the three recorded runs had P50 45–49 ms. `compat-matrix.md:127` puts the
   spread down to "the machine's load", which nothing measured.
   - **Scenario.** A user reruns `./scripts/eval.sh` from the README's Develop
     section, gets about 47 ms, and suspects a regression.
   - **Fix.** Give the range over the three runs, and drop the cause or label
     it unverified.
4. **The uninstall reloads before the user deals with `default.custom.yaml`,
   and nothing says to reload again.** `README.md:152` runs `--reload`, and
   the three decisions follow at `:155-162`. The block also leaves
   `$R/build/`, which holds the built translation schema.
   - **Scenario** (a derivation, not observed). The user pastes the block,
     then deletes the managed `default.custom.yaml`. The deploy that just ran
     still had the schema in its list. So `Ctrl+Shift+T` can go on reaching
     `朙月拼音·译` until the next deploy. `install.sh:32` also says Squirrel
     keeps loaded Lua until it restarts.
   - **Fix.** End with "then run the `--reload` line again", or with Install's
     step-3 restart.
5. **The matrix's rules for later rows are thin.**
   - `:38`, C5's "Supported when" is "Where the preedit and the prompt show",
     which is no rule, the gap red 1 had for C6 and C7. Requirements §2 says
     inline. So when Terminal's floating preedit is finally observed, nothing
     says whether it is "needs config" (`no_inline`) or not supported.
   - `:53`, "Messages", lost the plan's "a new message with no recipient".
     It now sits beside "an iMessage conversation". Whoever fills it in may
     open a conversation, the case the plan kept out for privacy, and one
     where Enter sends.
   - The plan's "Each cell says 'agent'" (`task-11-eval.md:34`) became the
     header's convention (`:7-8`). A cell the user fills in later would read
     as agent-observed. Add "unmarked cells: agent, this run".
6. **"12 come from the original plan" reads as "12 are real chat"**
   (`eval/sentences.txt:2`, testing.md `:114`). Rows 8 and 9 use
   `example.com` and `github.com/foo/bar`, which are placeholders, not a
   user's messages. Say that the 12 are the plan's examples, not checked as
   real chat, or someone will quote rows 1–12 (8/12) as the "real" subset.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| Every matrix cell is one of supported / needs config / unverified; none blank | ok; **the user's confirmation pending** | 98 of 98 cells start with a verdict (scripted). Pending with the user: Chrome's C6, `supported: jin tian … the user may judge otherwise`. Read literally, C6's rule, "what was typed lands … raw", does not cover a preedit with spaces added. If the user accepts it, the rule should say so |
| The 30-sentence set covers chat, code identifiers, URLs, emoji and mixed Chinese-English | ok | 8 / 6 / 5 / 5 / 6. `sentences.txt` equals the appendix's category and source on all 30 rows (scripted); `eval.sh` skips its three comment lines |
| translate evaluated on the 30 sentences: each judged (agent first, user confirms), P50/P95 recorded | agent's part ok; **the user's pending** | Every row has a verdict. Recomputed from the appendix: 7/8, 5/6, 1/5, 3/5, 5/6 = 21/30; nearest-rank P50 20 ms, P95 37 ms. `:150` says the user reviews them |
| The eval's conclusion on the default backend is written into compat-matrix.md and design §2 | ok | `compat-matrix.md:141-148`; `requirements.md:29`, where §2 lives |

### Verdict
0 red / 2 yellow — no red, the review gate is clear to close. Clear the two
yellows or defer each with a one-line reason. Acceptance items 1 and 3 still
wait on the user's confirmation, so the task is not done until the user has
confirmed.

---

### Author response to round 2
- **Yellow 1, fixed.** C1's "Supported when" gains back "nothing sent or run
  by either Enter". The README's chat-app sentence now says it was seen in
  WeChat, and that other chat apps are not yet checked.
- **Yellow 2, fixed.** The matrix's eval section opens with where the
  sentences come from:
  - 12 are from the plan, with placeholder URLs
  - 18 (rows 13–30) were composed by the agent
  - none is from real chat
- **Greens, fixed:**
  - With every request failed, the summary prints `n/a`, not `None`.
  - The Messages row keeps "a new message with no recipient".
- **Greens, deferred:**
  - The `ERROR ` prefix heuristic in `eval.sh`: no translation in this set
    starts so.
  - The overwritten results artifact: the judged run is in the appendix.
  - Reconciling latency across documents: the matrix states the variance.
  - The uninstall order around `--reload`.
  - A rule for C5.
  - Per-cell "agent" labels: the matrix's preamble says who observed.
- **Acceptance items 1 and 3:** the user confirmed the matrix and the eval
  verdicts on 2026-09-22, Chrome's `jin tian` as supported under C6 included.

---
