---
name: task-review
description: Review a task's diff against the design before it may be marked done; findings go to the feature's review-log.md. Use when closing a task, when the task-reviewer agent runs, or when asked to review a change.
---

# Task review

**Why this gate exists**: the things most easily got wrong in this project are
exactly the things unit tests cannot see. A test can verify what `decide()`
returns for six kinds of key; it cannot verify "on this path, was there a
`commit_text` before `ctx:clear()`". It can verify `config.load`'s defaults; it
cannot verify that the test itself can ever fail.

Review is not a formality. **Finding nothing is not good news, it is a signal** —
either the change really is clean, or the review was not deep enough.

## Scope

```bash
./scripts/progress.sh diffrange <n>     # e.g. 6283f9d4..HEAD
git diff $(./scripts/progress.sh diffrange <n>)
git status --short                       # uncommitted work counts too
```

Review only what this task touched. Do not comment on code it did not go near —
that belongs to another task.

## Read first

1. `./scripts/progress.sh show <n>` — the acceptance items are the floor for
   this review
2. the task's file under the feature's `plan/` — the plan contains code; where the
   implementation differs, **it must be stated whether that is an improvement
   or an omission**
3. The design sections the diff touches — each dimension below names its own

## Dimensions

The first five are red lines. Violating one is 🔴, full stop.

### 1. Never eat text (design §6.3)

Walk every path in the diff that reaches `ctx:clear()` and ask: before arriving
here, has a `commit_text()` **necessarily** committed either the Chinese draft
or the English translation?

Not "normally it would" — **every path**. Error branches, early returns, the
fallback after a failed pcall, all of them. One missing path means the user
loses a sentence they already typed: the worst thing this project can do.

### 2. One commit exit (design §3.1)

`engine:commit_text()` is permitted only in `ime_translate_processor.lua`. The
hook checks text; **you check semantics**: does the translator route around this
by producing a candidate for the engine to commit? Does the filter change
candidate text and thereby change what commits?

Both fatal defects of the original Plan A came from a candidate carrying display
and commit at once. Any construction that re-entangles those two is 🔴.

### 3. All three invalidation checks (design §6.2)

- in decide: anything but Enter / Shift+Enter / Esc is `invalidate_and_pass`
- at the top of each processor event: compare draft against snapshot
- before the translator produces: the same comparison

The third exists for mouse selection of a candidate, which produces no key
event. **A missing check is a whole class of stale-translation bug**, and none of
the three is visible to unit tests — tests only feed keys.

> **This dimension follows decision D1.** §6.1–§6.2 carry open-finding notes
> (design §12 R10): as written, the snapshot comparison reads the very candidate
> used for display, and the third check always reads stale. If D1 has closed,
> review against the rewritten §6 and the display mechanism the spike report
> recorded. If it is still open and the diff touches `session.lua`, the
> processor or the translator, **that is itself a 🔴** — the task should not
> have started (`progress.sh start` refuses it).

### 4. Session state never in a module singleton (design §6.1)

`phase` / `text` / `code` / `draft` belong in `Context` properties. librime-lua
gives every registered component one shared Lua state, so module-level state
leaks across **all** input sessions — switching app or input box crosses the
wires.

Config and api_key are process-wide read-only data; caching them at module level
is correct. The test: **would this value need to differ because the user moved
to another input box?** If yes, it must be in Context.

### 5. Shell escaping only via json.shq (design §7.3)

`string.format("%q", ...)` is Lua literal escaping: double quotes, inside which
`$()` and backticks still expand in a shell. The API key travels this path.

### 6. Can the test actually fail?

TDD's usual failure mode is not a missing test but a test that can never fail:

- the assertion is `assert(true)`, or there is no assertion
- the mock replaced the logic under test (e.g. mocking `backend.translate` and
  then testing `backend.translate`)
- implementation first, test written afterwards to transcribe current behavior —
  such a test locks bugs in, it does not catch them
- the plan's "run it to confirm it fails" step was skipped
- a structured payload (a JSON body, YAML, a command line) is checked only by
  substring: a request body that no parser accepts still contains every
  fragment a test looks for. Parse it and compare fields (hotfix
  2026-09-22, the openai request body)
- a code path no test or smoke row runs against the real counterpart: a
  backend adapter that never met a real server is unverified however green its
  unit tests are

When in doubt, prove it: break the corresponding implementation line, run the
test, **confirm it actually goes red**, then put it back.

### 7. Constants match the design

Check literally: `timeout_ms` = 1500 (not 3000); `max_chars` counts
**characters** (Lua's `#s` is bytes, Chinese is 3 each); `temperature` carried
only by the openai adapter (§7.7 — Opus 5 / Sonnet 5 return 400); anthropic's
`anthropic-version` header, top-level `system` field, required `max_tokens`, and
reading the result by walking `content[]` for `type=="text"` (§7.6).

Do all eight error codes (§8.1) have a path that produces them? Do the strings
match word for word?

### 8. Upstream assumptions are cited, not remembered

Any line that leans on how librime, librime-lua or Squirrel behaves — what
`get_commit_text()` returns, when a translator runs, what survives
`ctx:clear()`, which modifier bits arrive — must trace to something: an F-row in
design §15.2, or a verdict or constant in `docs/spike-report.md`. A comment that
asserts engine behaviour with no such anchor is 🟡; if a red line rests on it
(dimensions 1–3), 🔴.

The reason is R10: a whole section of the design was built on a plausible
sentence about `get_commit_text()` that nobody had checked, and the headless
tests agreed with it because the fake context did too. **A fake that returns a
fixed value cannot contradict the assumption it encodes** — when a test's fake
stands in for engine behaviour, ask where that behaviour was verified.

### 9. YAGNI and deviations

- Is there code for something v1 explicitly excludes (requirements §2's
  non-goals, §8.3's pre-translation)?
- Every place the implementation differs from the plan needs one sentence of
  explanation. **An unexplained deviation is itself a 🟡.**

## Severity

| | Meaning | Consequence |
|---|---|---|
| 🔴 | A red line (dimensions 1–5), text loss, a test that cannot fail, or a previously passing acceptance item broken | **The task cannot be marked done.** Fix it, or have the user explicitly accept it and record that in review-log |
| 🟡 | Should fix: unexplained deviation, a hole in error handling, naming that contradicts the design, duplicated logic | Fix, or defer with a one-line reason |
| 🟢 | Suggestion: simplification, readability | Advisory |

Every finding needs a **concrete location** (`file:line`) and a **concrete
failure scenario** (what input → what consequence). "Consider strengthening
error handling" has no scenario, so it is not a finding. Do not write it.

## Output

Append to the feature's `review-log.md`:

```markdown
## Task <n>: <name> — round <k>

Range: `<diffrange>`
Time: <UTC>

### 🔴 Must fix
- `rime/lua/ime_translate_processor.lua:87` — the error branch calls
  `ctx:clear()` before `commit_text`. Trigger: backend times out, user presses
  Enter, the whole draft sentence disappears (design §6.3, never eat text).

### 🟡 Should fix
- ...

### 🟢 Suggestions
- ...

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| lua tests/test_x.lua passes | ok | 14 assertions OK |

### Verdict
<n> red / <n> yellow — the task **cannot** be marked done | or: no red, clear to close
```

Any 🔴 means another round, until zero. **Append each round; never overwrite the
previous one** — what was found and how it was fixed is the only record this
project will have of why the code looks the way it does.
