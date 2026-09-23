# Review log

Every task is reviewed by `task-reviewer` before it is marked done. Task 2 is
manual; its record is `docs/smoke-report-006.md`.

---

## Task 1: The hint — round 1

Range: `2f874b8..HEAD` plus the uncommitted diff (`git diff HEAD -- rime/lua/ime_translate/state.lua rime/lua/ime_translate_processor.lua tests/test_state.lua tests/test_processor_mixed.lua`); `progress.json` out of scope
Time: 2026-09-23 22:14 UTC

### 🔴 Must fix
- None.

### 🟡 Should fix
- `rime/lua/ime_translate_processor.lua:204` — `draft ~= ""` does not
  guarantee `composition:back()` is a segment, and this line runs on every
  press, in idle too, where no pre-existing code called `back()`. librime-lua's
  `Composition:back()` returns nil on an empty composition (source reading,
  librime-lua `src/types.cc`, `CompositionReg::back`), while `get_commit_text()`
  on an empty composition returns the whole input (librime 1.16.0
  `Composition::GetCommitText`). `lock_literal`'s own "no segment to confirm"
  branch (lines 155-158) leaves exactly that state: all input unselected,
  `clear_non_confirmed_composition()` empties the composition, `add_segment`
  fails. Trigger, reproduced on the existing fake of
  `tests/test_processor_mixed.lua` "the segment cannot be added": after that
  Enter, the next press of `a`, Shift or Enter raises
  `ime_translate_processor.lua:204: attempt to index a nil value`; at HEAD the
  same three presses return 2, 2, 1. In librime-lua an error is logged and the
  key returns kNoop (`LuaProcessor::ProcessKeyEvent`), so the whole processor
  is skipped for that key: the Shift/Option watchers miss the press, and an
  Enter goes to the native chain instead of retrying the lock (fluid_editor
  commits the draft untranslated, unseen as English). Reachability in the real
  engine is low (librime's `AddSegment` fails only when the start differs from
  the current start, which the branch above already avoids), but the branch
  exists because the code treats it as possible, and the fix is one token:
  guard with `not ctx.composition:empty()`, as line 163 of the same diff
  already does. `show()` shares the weak guard but is never reached in idle,
  so it does not cover this case. Add a press after the "cannot be added"
  case to pin it.

### 🟢 Suggestions
- `rime/lua/ime_translate_processor.lua:162-163` — in the real engine the
  segment `back()` returns after the confirm is not the locked one: `OnSelect`
  sees `seg.end == input.length()`, marks it confirmed and `Forward()`s an empty
  segment `[n, n)` (upstream F20; librime 1.16.0 `engine.cc`), and the hint is
  written to that. It still shows: `GetPreedit` puts the caret after the last
  (empty) segment and inserts `GetPrompt()` = `back().prompt` there (F9), so it
  lands after the letters (source reading). The fake keeps the bare segment as
  `back()`, so the tests cannot tell the two apart. A clause naming F20 in the
  comment would save the next reader this derivation; Task 2's smoke is where
  it becomes measured.

### Paths walked and what was verified
- **Red lines.** No `commit_text` and no `ctx:clear()` added. The clearing
  writes only `prompt = ""`, only when the prompt equals `LOCK_HINT`, which no
  result (`  -> `/`  ☁ `/`  ☁✗ `) or error (`  ✗ `/`  ☁ ✗ `) prompt can equal.
  The lock is only decided in idle (`decide.lua`: result and error return
  before `unselected`), so the hint and a translation never coexist and
  `session.stale()` (idle -> false) is untouched. `commit_translation`'s
  on-screen check still works: mutation M4 below.
- **Order.** The clearing precedes the watchers, but only reads the prompt,
  so it cannot change a tap: a Shift press after the lock clears the hint, the
  release taps and locks/switches as before. Moving the clearing to the noop
  exit only (M5) passes every test, and I found no key for which it differs:
  every action that returns kAccepted in idle rewrites the prompt itself
  (`translate` via `show`, `literal_space` and `switch_backend` via `void`,
  `commit_draft` via `ctx:clear()`), so "before anything else" is not
  observable today. Not a finding.
- **Caret rule.** The lock is `on_draft`, so it runs only with the caret at
  the end; after it the caret stays at the end (F20 `OnSelect`). A later Left
  press clears the hint and passes on.
- **Hint left on screen.** BackSpace, Esc (idle: passed to the native chain,
  as before), Space, Shift+Enter, Enter, a Shift or Right Option tap: all are
  presses and reach this processor first (it is the first processor in
  `luna_pinyin_translate.schema.yaml`), with a non-empty draft (the locked
  letters are in `get_commit_text()`). The empty segment has no menu, so there
  is no candidate click to bypass the key path. Only the 🟡 state above
  escapes, and there by an error, not by leaving the hint.
- **Tests can fail** (scratchpad copy, each mutation reverted):
  M1 no hint write -> #54 fails; M2 drop `not k.release` -> #56 fails;
  M3 no clearing -> #58 fails; M4 clear any prompt -> #63 fails (`got nil
  want "Today's readme"`); M6 change `LOCK_HINT` -> `test_state` #19 and
  `test_processor_mixed` #54 fail. M5 survives, see Order.
- **Plan deviation.** Step 1's fifth test ("a translation's prompt is not
  cleared by a key press that is not a catch-all, e.g. a Shift press") is
  replaced by "Enter after the lock translates, Enter again commits". An
  improvement: in the result phase a Shift press is a catch-all
  (`decide.lua`), so the plan's case does not exist, and the Enter commit is
  the only place a wrongly cleared translation is observable (M4 proves it
  catches that). The test comment states the reason.
- **Language, constants.** Chinese only in `state.lua` and in test string
  literals; `LOCK_HINT` is byte-for-byte the design's `  ✓英文` (§5.5, §6.4).
  No module-level session state added.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | all files PASS; `test_processor_mixed` 93, `test_state` 19 assertions |
| After Enter locks letters the last segment's prompt is the hint, and nothing is committed | ok | #54, and "nothing committed" before it; M1 goes red |
| A release leaves the hint; the next key press clears it before anything else | ok | #56, #58; M2, M3 go red. "Before anything else" holds in code; not observable in tests (M5) |
| A translation or an error in the prompt is never cleared by the hint rule | ok | equality guard; #63, M4 goes red. An error's prompt is rewritten by every idle-or-error action anyway |

### Verdict
0 red / 1 yellow — no red, clear to close once the yellow is fixed or deferred with a reason

## Task 1: The hint — round 2

Range: `2f874b8..HEAD` plus the uncommitted diff (`git diff HEAD -- rime tests docs/design docs/features/006-lock-hint`); `progress.json` out of scope
Time: 2026-09-23 22:18 UTC

### 🔴 Must fix
- None.

### 🟡 Should fix
- None. Round 1's yellow is fixed: `rime/lua/ime_translate_processor.lua:206`
  now guards with `not ctx.composition:empty()`, the same guard as line 165,
  and `tests/test_processor_mixed.lua:203-206` presses a key after the
  "cannot be added" case.

### 🟢 Suggestions
- None.

### Paths walked and what was verified
- **The hint text.** `"  [en]"` in `state.lua`, both test files,
  architecture §5.5 and the §6.4 idle row, the decision entry and both plan
  files. No live `✓英文` remains (grep over `docs rime tests README.md`); the
  two hits are the decision entry recording the first version and round 1 of
  this log, both history. It is ASCII and cannot equal a result (`  -> `,
  `  ☁ `, `  ☁✗ `) or error (`  ✗ `, `  ☁ ✗ `) prompt, so the equality guard
  still never touches a translation or an error.
- **The fake's `empty()`** (`tests/processor_support.lua:75-76`). Now true
  exactly when `back()` returns nil, which is librime's own invariant
  (librime-lua `CompositionReg::back` returns nil only on `t.empty()`). It is
  not only for reachability: the fake's `clear()` sets `_text = ""` but leaves
  `_seg`, so under the old `empty()` the composition claimed a segment that
  `back()` would not return. Mutation F1 (old `empty()`, new guard) crashes
  `test_processor`, `test_processor_switch` and `test_processor_mixed` with
  `attempt to index a nil value`, which is the state after every commit.
  Does it weaken anything? The other callers of `empty()` are in
  `lock_literal` (lines 151, 154, 165), which runs only with a non-empty input
  and, in every test, a non-empty `_text`, where old and new `empty()` agree.
  So no existing assertion changes meaning; the fake got closer to librime,
  not looser.
- **The new test** (`test_processor_mixed.lua:203-206`). `ctx._seg = nil` is
  redundant (the failed lock has already left `_seg` nil through
  `clear_non_confirmed_composition` with a confirmed position of 0) but
  harmless: it pins the state the test names.
- **The comment** (`ime_translate_processor.lua:162-164`) now cites F20 for
  `back()` being the empty segment the confirm opened and F9 for where its
  prompt shows; both checked against librime 1.16.0 source in round 1
  (`ConcreteEngine::OnSelect`, `Composition::GetPreedit`). Still a source
  reading until Task 2's smoke.
- **Red lines, order, caret, taps, result-phase Enter.** Unchanged since
  round 1 apart from the guard; the round 1 walk stands. The guard reads the
  composition only, so it changes nothing for a non-empty composition.
- **Tests can fail** (fresh scratchpad copy, each mutation reverted; the four
  processor/state suites run each time):
  G1 guard back to `draft ~= ""` -> `test_processor_mixed` crashes at the new
  test; G2 no guard -> all three processor suites crash; F1 above;
  M1 no hint write -> #54; M2 release clears -> #56; M3 no clearing -> #58;
  M4 clear any prompt -> `test_processor_mixed` #63, `test_processor` #10,
  `test_processor_switch` #25; M6 hint value -> `test_state` #19 and
  `test_processor_mixed` #54. Baseline green.

### Acceptance re-check
| Item | Verdict | Evidence |
|---|---|---|
| scripts/run_tests.sh passes every file | ok | all PASS; `test_processor_mixed` 94, `test_processor` 103, `test_processor_switch` 78, `test_state` 19 assertions |
| After Enter locks letters the last segment's prompt is the hint, and nothing is committed | ok | #54; M1 goes red |
| A release leaves the hint; the next key press clears it before anything else | ok | #56, #58; M2, M3 go red |
| A translation or an error in the prompt is never cleared by the hint rule | ok | equality guard; M4 goes red in three suites |

### Verdict
0 red / 0 yellow — no red, clear to close
