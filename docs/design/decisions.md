# Decision log

Part of the design set — start at [overview.md](overview.md).

## 13. Decisions

### Open decisions

What is **not** decided yet. Everything below this section is history; this is
the part that still constrains work.

A row here is an open decision. `scripts/open-decisions.sh` is the only reader
of the table: `progress.sh start` refuses a task named in a row's **Blocks**
cell, and the session-start line lists the open IDs. Closing a decision means
deleting its row and writing the outcome as a dated entry below. Blocks tokens
are `<feature number>:<task>,<task>`; `-` means it blocks nothing. No literal
pipe characters inside a cell.

<!-- open-decisions:start -->
| # | Decision | Waits for | Blocks | Until then |
|---|---|---|---|---|
<!-- open-decisions:end -->

### First draft

- Everywhere-coverage → rule out side-car approaches as the primary path;
  choose the IME route.
- Build on Rime rather than writing a pinyin engine → pinyin quality and
  workload.
- Always fall back to the original text on translation failure → an IME's first
  duty is not to eat text.
- Send is always manual → translation errors must be interceptable.

### Second review

- Make the backend contract adapter-based → the original contract hardcoded the
  OpenAI shape, so non-OpenAI backends could not be plugged in.
- Delete the two-stage "translating…" candidate → the candidate window cannot be
  repainted while the same thread blocks; it does not hold logically.
- Support cloud APIs (user decision) → tiered trust model + Keychain +
  `temperature` demoted to an adapter-private parameter + two new cloud error
  codes.

### Third revision — Plan A′ (2026-09-07)

- **The product promise is not narrowed** (user decision) → keep normal
  segment-by-segment selection and punctuation habits; only the final English
  sentence commits.
- **Draft ownership assigned to Rime's composition**, no custom buffer →
  `fluid_editor` already provides "does not auto-commit" semantics, so B′'s
  rewrite cost is unnecessary.
- **Translation becomes a separate schema, not an option toggle** → swapping the
  editor only affects the translation schema, leaving normal Chinese input
  untouched; switching schemas rebuilds the context, so session state cleans
  itself up; toggle logic is handed back to native `key_binder`.
- **Display and commit responsibilities separated**, `engine:commit_text()`
  becomes the only commit exit → kills both "depends on the default Return
  binding" and "segment concatenation" in one move.
- **State moved from module singletons to `Context` properties** → librime-lua
  gives all components one shared Lua state, so module-level state leaks across
  input sessions.
- **Invalidation checked in three places** (decide / processor / translator) →
  clicking a candidate with the mouse generates no key event, so `decide` alone
  cannot catch it.
- **`Shift+Enter` added** → once the IME owns the draft there must be an escape
  hatch meaning "don't translate, commit the Chinese".
- **Latency split into two metrics**, local `timeout_ms` set to 1500 → the
  timeout value equals the worst-case freeze.
- **`busy` downgraded to unreachable** → unobservable while blocking
  synchronously.
- **Pre-translation demoted to a reserved interface** → "a custom daemon is
  required" is not a proven conclusion, and the chain for feeding an async
  result back into the UI has not been designed.
- **Compatibility upgraded from a six-app checklist to a matrix** → added focus
  change, typing during the wait, switching input method, mouse selection, and
  recovery after cancel.

### Documentation consolidation (2026-09-19)

- Three documents (design spec / implementation plan / backend research)
  consolidated into two: the design set plus the `docs/features/001-zh-en-ime/plan/` set.
- Section numbers §1–§13 kept verbatim, so plan.md's `design §X` cross
  references all remain valid.
- The backend research's measured evidence folded into
  [evidence.md §14](evidence.md). What was dropped as stale: references to old
  section numbers (§6/§11), the retired premises P1/P2, the machine recorded as
  macOS 26.3.1, and the "backend selection pending" three-option route — all
  three adapters are now fixed in [backend.md §7](backend.md), and the only open
  question left is **which one is the default**, decided by S8 plus the blind
  eval.

### Design review before Task 1 (2026-09-20)

A read-through of the design and plan, checked against upstream source
([upstream.md §15](upstream.md)). Nothing had been built; no task had started.

**Decided and applied:**

- **§5.3's punctuation fallback corrected** → the `{ commit: " " }` form still
  commits the whole draft, and the YAML patched the wrong shape. Plain string
  values keep the mark in the draft; the "lose the comma from the preedit"
  trade-off disappears. S2 is now expected to fail, and Task 1 verifies the
  fallback in the spike instead of discovering it in Task 10.
- **Spike extended with S11–S14** → S1 and S3 are, by source reading, the
  safest assumptions in the set; the Enter loop (S11), focus loss (S12) and the
  host application under a synchronous stall (S13) are what can actually
  overturn the design, and all three were first reachable in Task 10 — nine
  tasks of work later.
- **Risks R10–R15 recorded**, each labelled source reading, derivation or
  unverified. None is a measurement.
- **Three plan errors fixed before execution**: Task 10's punctuation fallback;
  Task 10's `key_binder`, which dropped `import_preset: default` and with it
  paging, Tab and the emacs keys; Task 6's timeout, floored to whole seconds so
  that the 1500 ms default became a 1 s ceiling. The plan is normally immutable
  ([../README.md](../README.md)) — that rule is about not bending the plan to
  fit a deviating implementation. These were errors in the plan itself, found
  with zero tasks started, and they are logged here rather than patched
  quietly.

**Left open**: D1 (display and staleness), D2 (focus loss), D3 (whether S11
joins the gate). Each waits for a spike result and for the user; they are
tracked in the open table at the top of this section, not here.

**Harness changes made alongside** — the review exposed three gaps in the
harness itself, not only in the design:

- **Open decisions became mechanical** → a finding that says "do not build on
  §6 yet" is exactly the kind of rule that loses to momentum when it lives only
  in prose. `scripts/open-decisions.sh` reads the open table;
  `progress.sh start` refuses a blocked task; the session-start line names what
  is open.
- **A design-review procedure exists** (`design-review` skill, `/design-review`)
  → every enforcement layer so far guarded the *implementation* against the
  design. Nothing guarded the design against upstream reality, and the gate
  happened to sit on the two safest assumptions. The skill fixes the procedure
  and the evidence labels: source reading, derivation, measurement.
- **The language check judges an Edit against the rebuilt file** → checking the
  bare fragment as prose refused two legitimate edits in one session, both
  quoting Chinese punctuation inside a fenced YAML block.

### D3 closed: S11 joins the gate (2026-09-20)

**Decision (the user's):** S11 becomes a life-or-death gate item alongside S1
and S3, and S11-S14 all enter Task 1's acceptance list.

Applied to `docs/features/001-zh-en-ime/progress.json` — `gate.id`,
`gate.description`, Task 1's `gate` field and its `acceptance` list. Those are
**definition** fields, changed only by a user decision and only with an entry
here ([../features/README.md](../features/README.md)).

**Why S11 and not only S1/S3.** The 2026-09-20 review established that S1 and
S3 are, by source reading, the safest assumptions in the set, while the Enter
loop is where the design can actually come apart ([upstream.md §15.3](upstream.md)).
A gate sitting on the two safest checks does not gate anything. The recorded
acceptance list also let Task 1 close with S11 never run, which is precisely
the hole the review meant to close.

**What falsification means is not the same for all three.** S1 or S3 falsified
⇒ Plan A′ does not exist: stop, return to design, evaluate B′
([architecture.md §3.5](architecture.md)). S11 falsified ⇒ §6.1-§6.2 go back to
design review before any implementation continues; Plan A′ itself may still
stand, because the draft-versus-display problem is confined to how the
translation is shown and versioned. Both halt the tree; only the first kills
the plan.

**S13, S12 and S14 enter acceptance but not the gate.** S13 is pass/fail only
at 1.5 s — at 4 s a failure is a recorded threshold for the cloud `timeout_ms`
ceiling, not a stop. S12 and S14 are record-only by construction
([testing.md §10.2](testing.md)); their acceptance is that the report holds the
observation, not that the observation came out a particular way.

**Binary reading taken the same day** (source reading, not a measurement): the
installed Squirrel is CFBundleVersion 1.1.2 carrying **librime 1.16.0**
(`otool -L` current version and the embedded `rime_version` string agree), with
`librime-lua.dylib` present. Per [upstream.md §15.2](upstream.md) F6 that is the
1.11.2-and-later branch, where the trailing empty segment **is** translated — so
§15.3's State A derivation applies on this machine, and it ends in a
re-translate loop that never commits. The spike report records the versions as
measured; this note only says which branch the derivation now points at.

**Still open**: D1 and D2, both waiting on spike evidence.

### Task 1 spike: three acceptance items accepted as recorded (2026-09-20)

**Decision (the user's):** three acceptance items of feature 001 Task 1 that the
spike could only partly meet are accepted as recorded rather than measured.

| Item | What was recorded instead |
|---|---|
| S7, Slack row | Slack is not installed on this machine: unverified |
| S13, Slack rows | Slack is not installed on this machine: unverified |
| S8, the apfel half of "translate vs apfel" | apfel cannot run here — `device not eligible`, HTTP 503 on every completion — so its failure mode is recorded in place of a latency baseline |

The acceptance list in `progress.json` is left as written; this entry is what
closes those three items. Evidence: `docs/spike-report.md`.

**Not decided here:**

- **The S1/S3/S11 gate** stays `unverified`. The user is holding the verdict
  pending a review of the spike report — in particular because most of the
  evidence from S11 on was gathered by the agent driving the machine, where
  `CLAUDE.md` asks for a human observer. Task 1's Step 11 records the verdict,
  so the task stays in progress until then.
- The findings the report lists for design review — among them that the design's
  default backend (apfel) is unavailable on this machine, and that the whole
  synchronous stall must stay under about 2.5 s — open no decision by
  themselves. D1 and D2 now have the evidence they were waiting for; closing
  them is the user's call.
- **Opened the same day, at the user's request: D4**, the default backend —
  apfel cannot run on the development machine. Apple does not make
  FoundationModels available for the machine's device region, as its own
  eligibility record shows.

### D4 closed: `translate` is the default backend (2026-09-20)

**Decision (the user's):** apfel cannot run on this machine, so the default is
`translate` — the local NMT behind the libretranslate adapter
(`http://127.0.0.1:8989`, no model).

Evidence: apfel's FoundationModels domain fails on the device region (Apple's
regional availability); `translate` measured P95 21 ms warm, 93 ms cold,
about 40 ms through Lua's `io.popen` (`../spike-report.md`, S8). The known cost is
R4 — NMT skews formal — plus a lost space before URLs.

**Applied:**

- Design: §2's backend row names `translate` as the default; §7.4's note says
  apfel is not the product default; §10.4's note says the eval measures
  `translate` rather than choosing between it and apfel; §11 installs `translate`
  and describes the model download as measured.
- Plan, fixed before the tasks start (the plan is immutable only once a task has
  started): the README's config defaults, and Task 5's `DEFAULTS` and the tests
  that assert them. Task 5 also changes in one more place: when tiered trust
  rejects a remote `base_url`, the whole backend triple (`backend`, `base_url`,
  `model`) now falls back, not `base_url` alone. With a libretranslate default,
  falling back only the URL would leave an openai or anthropic adapter aimed at a
  libretranslate server — safe, since nothing is eaten, but the error would be
  misleading.
- **Not yet applied:** Tasks 10 and 11 still name apfel (its LaunchAgent, the
  config template, the `:11434` smoke test, the translate-vs-apfel eval). Each
  plan file now opens with a note saying it must be revised before it starts. The
  matching deliverable (Task 10) and acceptance item (Task 11) in `progress.json`
  are definition fields; the user changes them when those tasks are prepared.

### Gate S1/S3/S11 recorded as pass; Task 1 closed (2026-09-20)

**Decision (the user's):** the gate passes on the spike report's evidence.

- S1, S3 and S11 hold. S11 holds only with `segment.prompt`; D1, which turns that
  into the design of §6.1–§6.2, is still open and still blocks Tasks 7 and 9.
- **The user accepted agent-gathered evidence.** `CLAUDE.md` asks that a human
  observe Tasks 1, 10 and 11 on the real machine. S1–S4, S9 and S10 were observed
  by the user; from S11 on, the agent drove the machine at the user's request —
  keystrokes through System Events and CoreGraphics, screens through
  `screencapture -x`, text read back over AppleScript. The report labels how each
  verdict was taken. Whether that becomes the standing rule for Tasks 10 and 11
  is not decided here.
- Task 1 closes with the three acceptance items accepted as recorded (entry
  above). Documentation-only, so the review gate does not apply.

### Chinese test data allowed in `tests/*.lua`; Task 3 plan amended (2026-09-20)

**Decisions (the user's), both from Task 2:**

- **The language check now admits Chinese inside string literals in
  `tests/*.lua`.** `rules/core.md` already named Chinese test sentences as data,
  but `checks_language` granted no form for them in test files, so Task 2's plan
  test was refused and plans 03–07 carry more than forty such lines — Task 4's
  test compares eight Chinese error strings word for word. The check now
  tokenises a test file left to right and drops string literals before looking
  for Han characters: a `--` inside a string is not a comment, and a comment is
  still refused even when it quotes Chinese. Long strings (`[[...]]`) are not
  recognised, so Chinese in one is still refused — failing closed. Product code
  under `rime/lua/` gets no such allowance. Eight new assertions across both
  suites (Claude layer 66/0, git layer 25/0); every test block in plans 03–09
  passes the new rule.
- **Task 3's plan gains a control-character round trip.** Task 2's review found
  that no test reaches `json.escape`'s control-byte path — four deliberate
  breakages all passed. Adding the assertion to Task 2 would have changed its
  acceptance count, so Task 3's test now round-trips `decode(escape(s)) == s`
  over bytes 0–31, 127, `"` and `\` (35 assertions). Task 3 has not started, and
  its acceptance ("passes every assertion") names no count. Dry run of the
  amended plan against Task 2's committed `json.lua`: 59 assertions OK, under
  both a C and a UTF-8 ctype.

### D5 opened: the script of the draft (2026-09-21)

**Opened at the user's request**, after the user found Squirrel committing a mix
of what looked like Traditional and Simplified characters. That was
`luna_pinyin` behaving as shipped: its `simplification` switch has no `reset`,
so it outputs Traditional, and its Traditional standard writes some characters
in forms that look Simplified. The user switched their own `luna_pinyin` to
Simplified with a local `~/Library/Rime/luna_pinyin.custom.yaml`
(`switches/@2/reset: 1`) — machine configuration, outside this repository.

The same question, asked of the translation schema, has no answer in the
design: Task 10 keeps the `simplifier` filter but declares no switch for it.
Read from librime 1.16.0 source ([upstream.md §15.2](upstream.md) F13–F14), the
option then follows whatever state the session carried in — Simplified when
entered from `luna_pinyin` on this machine, Traditional when a session starts in
the translation schema ([upstream.md §15.4](upstream.md), a derivation). The
user has said they want Simplified; which way the schema declares it is D5, and
closing D5 is the user's call.

Nothing in the plan was changed. Task 10 already opens with a revision note
(D4); D5 adds to what that revision has to settle.

### D5 closed: the switch is declared without `reset` (2026-09-21)

**Decision (the user's):** the draft's script stays switchable. The translation
schema declares the `simplification` switch **without `reset`** — not forced to
Simplified, not left undeclared.

**Applied:**

- Design: [architecture.md §4.1](architecture.md) — the schema row names the
  switch, and the open-finding note became a note stating the rule.
  [upstream.md §15.4](upstream.md) gains what changes under this outcome.
- Plan, fixed before the task starts: Task 10's schema declares
  `simplification` between `full_shape` and `ascii_punct`, `luna_pinyin`'s own
  order. Task 10 has not started, so the plan is still open to correction.

**The known cost.** With no `reset`, nothing forces the option on. A session
that starts in the translation schema before the option has ever been saved is
Traditional ([upstream.md §15.4](upstream.md), a derivation). Toggling it once
from the switcher menu — in either schema — saves it. The local
`luna_pinyin.custom.yaml` (`reset: 1`) keeps `luna_pinyin` itself Simplified but
writes nothing to `user.yaml`.

**Not done:** no smoke check was added for the script. Task 10's acceptance is
"all 16 real-machine smoke checks", a definition field; a seventeenth check is
the user's call. The measurement that would settle §15.4 is written there.

### D1 closed: the translation is shown through `segment.prompt` (2026-09-21)

**Decision (the user's):** the translation is displayed through the last
segment's `prompt`, and the draft snapshot taken with `get_commit_text()` stays
the version. Asked at the same time and also the user's: the error reason is
shown the same way, and the translator and filter components are dropped.

**Evidence** (`../spike-report.md`, S11): the candidate display failed in both
states — with every segment confirmed the second Enter re-translated, with the
last segment open the candidate sat at position 4 and Enter committed English
never shown — while `segment.prompt` closed the loop in both. Row 5a showed the
draft working as its own version once the display stays out of it. The error
half is a derivation from the same run: with every segment confirmed there was
no candidate window at all, so a reason hung on a candidate's comment would not
be seen.

**Applied:**

- Design: [architecture.md](architecture.md) §3.1 (the display/commit split
  restated), §4.1–§4.3 (one Lua component; session.lua also gives the prompt
  text), §6.1 (the open finding replaced by why the version now holds), §6.2
  (two checks; the translator's third is gone, its residual stated) and a new
  §6.4 (the display, and what about it is not measured);
  [backend.md §8.1](backend.md) (the reason goes into the prompt; the
  `ShadowCandidate` constraint is gone); [risks.md §12](risks.md) R10 (closed);
  [testing.md §10.2](testing.md) S6 (moot).
- Plan, fixed before the tasks start: Task 7's `session.lua` gains
  `session.prompt(ctx)`, the text to show for the current phase, so the display
  is unit-tested; Task 9 is reduced to `shared` and the processor, which writes
  and clears the prompt. **Definition fields changed** in `progress.json`, under
  this decision: Task 9's description, its deliverables (the translator and
  filter files removed) and two acceptance items (the load test covers two
  modules; two invalidation checks, not three).
- Harness: `inject-design-context.sh` maps the processor and `session.lua` to
  §6.4, and drops the two components; the commit-exit message in `checks.sh`
  no longer names them.
- **Not yet applied:** Task 10's schema still inserts `lua_translator` and
  `lua_filter`, and its smoke rows describe the translation as a candidate. Task
  10 already opens with a revision note (D4); D1 is added to it.

**Not measured, owned by Task 10's smoke checks** ([architecture.md §6.4](architecture.md)):
the result-phase Esc clearing the prompt; a mouse click on a candidate while
the prompt shows; the prompt with the caret not at the end; long English prompts
per application.

### Task 9 review: the caret, and Esc after a no-key edit (2026-09-21)

**Decisions (the user's)**, both on findings of Task 9's review, round 1:

- **Enter and Shift+Enter with the caret inside the input only move it to the
  end.** The next press acts on the whole draft. The finding was red: librime
  composes up to the caret (source reading, [upstream.md §15.2](upstream.md)
  F15), so committing `get_commit_text()` and clearing lost the input after the
  caret, and Enter translated only the part before it. Of the options offered,
  moving the caret and acting in the same press was not chosen, because it
  would commit or translate a conversion of the tail the user has not seen.
  "Empty" is read from the input, which is what `ctx:clear()` removes. (First
  written here as "with the caret at the start the commit text is empty";
  round 2 of the review showed librime composes the whole input there, so at
  the start the rule costs one extra press and nothing else. Corrected the same
  day, with F15.)
- **An Esc in the same event in which check 2 voided a stale prompt is taken
  as in `result`**: the prompt goes, the draft stays. The finding was yellow: a
  no-key edit such as paging the candidate window with the mouse left the
  prompt on screen, check 2 reset the phase to `idle`, and the Esc reached the
  native `CancelComposition`.

**Applied:** [architecture.md](architecture.md) §5.2 (both rules), §6.2 (the
residual), §6.3 (the whole draft); upstream.md F15; the processor and its tests
(Task 9); `session.lua`'s comment. Task 10's revision note gains the smoke rows
that measure both.

### Task 10 revised before start; D5 amended (2026-09-21)

**Decisions (the user's)**, taken while revising Task 10's plan before it
started:

- **The translation schema pairs with `luna_pinyin_simp`**, the user's daily
  schema (`user.yaml` `previously_selected_schema`), not with `luna_pinyin`.
  `Ctrl+Shift+T` goes back to `luna_pinyin_simp`.
- **D5 amended: the script switch is `zh_simp` with `reset: 1`**, as in
  `luna_pinyin_simp`. The draft is Simplified whenever the schema loads, and it
  can be switched for the session, but the switch is not saved. D5 had closed
  as "`simplification` without `reset`".
  - Under the pairing, `zh_simp` without `reset` would be Traditional in every
    session that starts in the translation schema. `zh_simp` is not in
    `default.yaml`'s `switcher/save_options`, so it is never restored.
  - The first description of the pairing given to the user left that case
    out. The user chose again once it was stated.
  - This is a derivation, [upstream.md §15.4](upstream.md). Smoke row 16
    measures it.
- **`Control+g` / `Control+bracketleft` are accepted knowingly** (Task 8
  review, yellow 4). They are cancel keys, and in idle the native chain already
  clears the draft on them. The alternative was a copied binding list that
  would drift from the preset. Smoke row 25 records it.
- **Definition fields changed** in `progress.json`, Task 10:
  - apfel's plist is dropped from the deliverables (D4).
  - The first acceptance item becomes "every smoke check in Step 6 passes:
    gate rows as specified, record rows once the observation is written down".
  - The gate id `smoke-16` becomes `smoke`: the list grows from 16 checks to 28
    rows, picking up every open item from the reviews of Tasks 5-9.
- **Observation for Task 10's smoke checks.** The agent drives the machine and
  records what it reads back: keystrokes through System Events and CoreGraphics,
  `screencapture -x` only after checking which window is frontmost, and text
  read back over AppleScript. The user watches the rows marked 👁: the first
  loop, the mouse rows, and WeChat's send. Every row's record says how it was
  observed. This is the standing rule for Task 10. Task 11 is not decided here.

**Applied:**

- Plan: `task-10-wiring.md` is rewritten. The schema is a full copy of the stock
  `luna_pinyin.schema.yaml` with seven marked changes; that is the form the
  spike measured. `default.custom.yaml` appends to `schema_list`. The installer
  binds `rime.lua`, never overwrites a `default.custom.yaml` that is not the
  project's, and always installs the `translate` service. The smoke list is
  rewritten.
- The installer's file logic was run twice in a sandbox, with `launchctl` and
  Squirrel stubbed:
  - The second run changed nothing.
  - A foreign `default.custom.yaml` was left alone.
  - A `rime.lua` with no trailing newline got the binding on its own line.
  - A changed schema was backed up.
- Design: [architecture.md](architecture.md) §4.1 (the schema and
  `default.custom.yaml` rows, the D5 note) and §5.1;
  [upstream.md §15.4](upstream.md).
- The plan README's task table, the `plan-execution` skill's gate wording, and
  a note on Task 11's matrix.

### Task 10 smoke: Enter commits only a translation on screen (2026-09-21)

**Decision (the user's).** Smoke row 22, observed by the agent, showed what
Task 9's review, round 2, had derived:
- In state B with the prompt showing, a click on the highlighted candidate
  confirms the segment and opens an empty one after it.
- The prompt vanishes while the draft stays the same, so check 2 does not fire.
- The next Enter committed English that was no longer on screen.

The user had deferred the finding to Task 10 on the condition that it be fixed
before Task 10 closes if it were measured. Of the two fixes offered, the user
chose the narrower one: `commit_translation` commits only while the translation
is the prompt on the last segment. Otherwise that Enter shows the translation
again, with no backend call because the draft is unchanged, and the next Enter
commits it. Extending check 2 to compare the prompt on every key was not chosen,
because it touches every event.

**Applied:**
- The processor, and a test in `tests/test_processor.lua` (81 assertions).
- [architecture.md](architecture.md) §6.2 and §6.4.
- Re-run on the machine and observed by the agent: after the click, Enter
  showed `今天不过  -> Today is just` again with one backend call in the log,
  and the second Enter committed it. Rows 4-6 were re-run after the change and
  still pass.

### Task 10 review, round 1: agent observation accepted; D6 opened (2026-09-21)

**Decisions (the user's)**, on Task 10's review, round 1:

- **Agent observation is accepted for the rows marked 👁** (4, 5, 22, 23, 27).
  The plan had them watched by the user. None was watched live: the agent drove
  and read back each one. The smoke report says so row by row, and "measured" is
  not used for them. This settles the round's red, the red line "a human
  observes the real machine" (`CLAUDE.md`), for Task 10 only; Task 11 is not
  decided here.
- **Row 21 as well** (after round 2). The user asked the agent to run it:
  "You can do the test by yourself". A posted trackpad-like scroll gesture
  paged Squirrel's window with the prompt showing, and Esc kept the draft. It is
  labelled "agent, at the user's instruction".
- **D6 opened**: which schema a new session starts in. Architecture §5.1 said
  "the normal schema is the default at login", which is false (librime starts
  a session in the previously selected schema; smoke row 16). §5.1 is corrected;
  whether to change the behaviour is D6. It blocks nothing, because the default
  backend is local.
- **Full-width punctuation is plain strings too** (review yellow 4). `full_shape`
  is saved by the switcher and restored in every session, and its preset marks
  are `{ commit: … }`, which would commit the whole Chinese draft untranslated.
  The schema's change 4 now covers `full_shape`. This is a deviation from Task
  10's plan, which is immutable once started, and it is recorded in the smoke
  report.

### Shift+Enter switched the IME to English; Shift now switches nothing in the translation schema (2026-09-21)

**Found by the user in use**, after the Task 10 smoke run: after Shift+Enter the
IME was in English, and getting back to Chinese took two switches.

- **Reproduced by the agent** with the events a physical Shift+Enter sends:
  Shift down, Return down and up carrying Shift, Shift up. `今天` committed, and
  the next `n` went into the document as a plain letter.
- **Cause, from source reading of `ascii_composer`.** A Shift released with no
  other key seen in between (within 500 ms) toggles `ascii_mode`, and any other
  key resets that state. The processor sat first and took the Return, so
  `ascii_composer` never saw it.
- **Why smoke row 11 missed it.** Its Shift+Enter was one posted Return event
  carrying the Shift flag, with no separate Shift press or release.

**First fix, withdrawn the same day.** In the schema, the processor moved to
right after `ascii_composer`; it still preceded `key_binder`, `speller` and
`fluid_editor`. This deviates from Task 10's plan ("the processor must come
first"), which is immutable once started, and it is recorded in the smoke
report. Re-run by the agent with the same event sequence:
- After Shift+Enter, `n` stayed pinyin with candidates.
- Enter, Enter still translates and commits.
- Shift+Enter with a translation showing commits the Chinese and stays in
  Chinese.
- A lone left-Shift tap still toggles English.

[architecture.md §4.1 and §5.2](architecture.md).

**Revised after Task 10 review, round 3 (the user's decision).**
- **The finding (red, a derivation).** Behind `ascii_composer`, the processor no
  longer sees every Enter first:
  - In inline English, after Caps Lock (`good_old_caps_lock`),
    `ascii_composer`'s `ProcessCapsLock` rejects an Enter carrying the Lock bit
    to the application. That is spike R15's lost draft.
  - librime master `74bd5dc` (unreleased) adds a commit of the raw input on Enter
    or space in ascii mode at the same place. The processor-first order covers
    the Enter half. The space half would still commit the raw input, but only
    in ascii mode with a draft open. That is unreachable here on 1.16.0: Shift
    is `noop`, and Caps Lock clears first.
- **The fix now.** The processor goes back first. `ascii_composer`'s `Shift_L`
  and `Shift_R` are `noop` in the translation schema (schema change 8), so
  there is no Shift toggle for Shift+Enter to trip.
- **The cost.** Shift switches nothing in this schema until feature 002. The
  remaining ways into English with a draft open, Caps Lock and
  `Ctrl+Shift+T`, both discard the draft. Feature 002's design puts the Shift
  tap in the processor anyway; it was agreed with the user the same day and is
  not yet in this repository.
- **Verification: measured by the user, on the physical keyboard.** After
  Shift+Enter, pinyin still showed the candidate window in Chinese. After a
  lone Shift tap, it was still Chinese. The agent's own attempts could not
  settle it:
  - Posted Shift events reached Rime only intermittently.
  - A control in `luna_pinyin_simp`, where a tap should toggle, did not toggle.
  - Task 10 review, round 4 also showed that one earlier agent run could not
    tell the fix from the defect.
  - The agent's runs are recorded in the smoke report. The pass rests on the
    user's observation.

### Feature 002 designed: mixed input by a Shift tap that locks the segment (2026-09-21)

**Decisions (the user's)**, taken in brainstorming:
- **The goal.** Mixed sentences are translated whole, and the English words are
  kept.
- **The input: switch the system-IME way.** Tap Shift to switch to English, and
  tap it again to switch back. English candidates in the menu, and automatic
  detection, were not chosen.
- **Right Shift behaves like left.**
- **The mode persists after a commit.**
- **A draft with no Chinese** commits on Enter without translation.

**Evidence.** A throwaway spike, observed by the agent, in the installed copy
only. It was removed afterwards: `install.sh` restored the schema, and the
spike's Lua file and `rime.lua` lines were deleted.
- Rime's own `inline_ascii` re-read the English as pinyin on switching back.
- An `ascii_mode` option notifier fired after the re-reading, which was too
  late.
- Locking and then switching, from one key (F12 standing in for the tap), gave
  - `请你整理一个readme文件` → `Please sort out a readme file.`
  - `今天readme好的`
  - `请pull request好的`
  - `用git提交README文件` → `Use git to submit the README file`

  A physical Shift tap driving the lock is not measured: the agent's posted
  Shift events were unreliable.

**Applied.**
- [architecture.md](architecture.md) §4.1 (two new components; processor and
  decide rows), §5.2 (the Shift tap row; Enter on a draft with no Chinese) and
  a new §5.5.
- [upstream.md](upstream.md) F19–F22, read while planning:
  - English mode's segment and keys
  - why the lock must come before the switch
  - what Squirrel sends for Shift
  - librime-lua's millisecond clock

  F22 keeps design §4.1's 500 ms tap window buildable. Without it the plan
  would have had to drop the window.
- Feature 002's plan and ledger follow in `docs/features/002-mixed-input/`.
- Nothing in 001 is blocked.

### Design review before feature 002 Task 1; D7 opened (2026-09-21)

The `design-review` procedure, run on §5.5 and feature 002's plan before Task 1.
Sources read:
- librime at tag 1.16.0
- Squirrel at tag 1.1.2
- librime-lua on master

The findings are [upstream.md](upstream.md) F23–F26 and the derivations in
§15.5.

**The verdict: the skeleton holds.** Step by step through `Compose` and
`CalculateSegmentation`, the tap works as the spike saw it:
- a pinyin segment is confirmed, and an empty segment opens after it
- the switch recomposes only that empty segment
- the first English character replaces it with a `raw` one, which the raw
  candidate answers

It holds after a selection and with two taps in a row. Every librime-lua
binding the plan uses exists as used (F25). The Shift events themselves are
known to reach librime on this machine. In 001, `ascii_composer` took a
physical Shift release for a tap: the user saw the IME switch to English.

**New findings.**
- **R16, derived: Caps Lock after a tap replaces the whole draft.** That breaks
  §6.3. **D7 is opened** and blocks Task 5, the task that writes the schema.
- **R17, derived: BackSpace across a lock.** It reads the rest of a locked
  segment again in the current mode. Nothing is lost. Recorded, with a
  workaround; no decision opened.
- **The mode is per Rime session (F24).** Squirrel's `app_options` start VS
  Code, Xcode, Terminal and others in English.
- **`Control+Shift+2` switches without locking.** It is the preset's own
  `ascii_mode` toggle.
- **A highlighted candidate shorter than its segment** locks only what it
  covers.

**Applied.**
- architecture.md §5.5: the per-session mode, three new edges, and an
  open-finding note for D7.
- risks.md: R16 and R17.
- upstream.md: F23–F26 and §15.5.
- The plan, before any task started:
  - Task 6's rows 14 and 16 gained their expected results.
  - Rows 23–28 are new. Row 25 is a gate: no text lost under whatever D7
    decides.
  - The README says Task 5 waits for D7.

**Settled by measurement.** Every derivation above is settled by the Task 6
row it names. No S-item is added: feature 002 has no spike task, and Task 6 is
where a person watches.

### 002 Task 1 review: a two-Shift roll (2026-09-22)

The reviewer read Squirrel: a Shift event is sent only when the Shift flag
changes. So a roll of both Shifts reaches Rime as a left press and then either
a left release, which is a tap, or a right release, which `shift_tap` does not
count. `ascii_composer` toggles on both.

**Applied.**
- Task 1's test now uses the streams Squirrel sends. The deviation from the
  plan's code is recorded in the review log.
- The module's comment no longer claims to be exactly `ascii_composer`'s rule.
- F21 is narrowed.
- Task 6 gains record row 29, since that task has not started.

A roll is rare, and a stray switch loses no text, so the module's rule stays as
planned.

### 002 Task 2 review: one Enter for a draft with no Chinese (2026-09-22)

Task 2's review noted a consequence of the user's §5.5 decision. A draft with
no Chinese commits on the **first** Enter. The Enter-Enter rhythm of 001 then
sends a second Enter to the application, and in a chat box that is a send.
- The IME itself still sends nothing (§2), and native Rime behaves the same.
- Task 6 gains record row 30, since that task has not started. It is to be
  shown to the user with the smoke results.

### 002 Task 3 review: the raw translator is not needed for the lock; D8 opened (2026-09-22)

The reviewer read `Context::ConfirmCurrentSelection` (F20). A non-empty segment
with no candidate is confirmed as raw input, the select notifier fires, and it
returns true; only an empty segment returns false. `GetCommitText` takes such a
segment's input, which is the same text the translator would have offered.

§5.5's reason for the translator — "confirming it would do nothing" — was
therefore wrong, and it is corrected with a note. The earlier transcript shows
the spike included the translator from its first version on that assumption,
and never ran without it.

Keeping it is a design choice, and it has a visible cost: a one-item candidate
window while English is typed. **D8 is opened** and blocks Task 5 alongside D7.
Task 3 closes with the module as specified, unwired. Task 6 gains record
row 31.

### 002 Task 4 review: install.sh waits for D7; a gate row for select-then-tap (2026-09-22)

- **`install.sh` waits for D7.** The installed schema, from 001 Task 10,
  already puts the processor first, with Shift `noop` and `Caps_Lock: clear`.
  `install.sh` copies every Lua file, so running it for any reason puts the
  Shift tap live, and R16 with it. D7's "Until then" cell now says so. Whether
  to accept that window instead is the user's call.
- **A gate row for select-then-tap.** The processor ignores the confirm's
  result, which is right: after a selection the confirm meets the empty
  segment and returns false (F20). That path is common, and no gate row
  covered it: row 4 excludes a selection, and row 14 is record-only. Task 6
  gains gate row 32, since it has not started.

### Feature 002 redesigned: the Enter way; D7 and D8 closed (2026-09-22)

**The user's decisions**, taken in brainstorming:
- **The habit of the macOS Pinyin IME.** Type English letters, press Enter,
  and they go into the draft as typed. No Shift switching is needed.
- **Enter depends on the draft's state.**
  - With unselected pinyin left, Enter locks it as the letters typed.
  - With nothing unselected, Enter translates.
  - Accepted cost: to translate, select the Chinese first. Enter on unselected
    pinyin turns it into letters.
- **Space with nothing unselected** adds a literal space to the draft.
- **The Shift tap stays**, as a supplement for English with digits and
  punctuation.
- **The approach reuses the lock** rather than adding a component. The user
  chose "approach A". Its no-mode-switch variant was then taken, because
  switching the mode makes Squirrel show a notice (F24).
- **D7 closed: `Caps_Lock: noop`** in the translation schema, schema change 9.
  It closes R16, and 001 smoke row 26's path.
- **D8 closed: the raw translator is dropped.** The module and its test are
  deleted, and the schema gains no translator line.

**Evidence.** A throwaway spike, observed by the agent in the installed copy
only.
- **The mechanism tried:** a processor placed first that, on Enter with
  something unconfirmed, ran `clear_non_confirmed_composition`, added a bare
  segment and confirmed it. On Space with nothing unconfirmed it pushed a
  space and confirmed that.
- **Results:** see architecture.md §5.5, "Evidence".
- **A first version called `get_confirmed_position` on the composition.** It
  failed silently: nothing in any Rime log, while Enter fell through to 001's
  translation. A `pcall` showed "attempt to call a nil value". The call belongs
  on `toSegmentation()` (F27).
- **Restored afterwards:** the schema and `rime.lua` came back from backups
  (`install.sh` was not run: D7 was still open), the spike module was deleted,
  Squirrel was redeployed and restarted, and the input source was set back to
  ABC as found.

**Applied.**
- architecture.md: §5.5 is rewritten, the §4.1 and §5.2 rows are updated, and
  the `ime_translate_raw` row is removed.
- upstream.md: F27.
- risks.md: R16 is closed, and R17 updated.
- The plan: a new Task 7 (the Enter and Space rules); Task 5 revised for
  D7/D8, now after Task 7; Task 6's rows revised. The ledger definition
  changes by this decision.

### 002 Task 7 review: English mode, Shift+Space, the smoke rows (2026-09-22)

- **The user's decisions: English mode.** In English mode the open part is
  letters already, so nothing counts as unselected. Enter translates a draft
  with Chinese at once, and commits one with none as is. Whether to translate
  depends on the draft's content, never on the mode.
- **Shift+Space.** It takes the literal-space rule as well. `fluid_editor`'s
  key map falls back from Shift+Space to Space, which would commit the draft
  untranslated (F27, the reviewer's source reading).
- **Applied.**
  - The code, as deviations recorded in the review log.
  - architecture.md §5.5, and the §5.2 Space row.
  - Task 6, which has not started:
    - rows 1, 6 and 22 select before Enter
    - row 21 records that State B with a prompt can no longer be reached
    - row 45 spells out exactly two Enters in WeChat
    - new rows 46 and 47

### 001 Task 11 revised before start (2026-09-22)

**The user's decisions:**
- **The eval measures `translate` alone.** apfel cannot run on this machine
  (D4).
  - Each of the 30 translations is judged acceptable or not: the agent first,
    then the user confirms.
  - P50/P95 are recorded.
  - `translate` stays the default unless the eval gives a reason to open a
    decision.
- **The agent composes the 18 sentences the set lacked,** marked as not from
  real chat. The set gains a sixth category, mixed Chinese-English, for
  feature 002.
- **The agent drives and observes the compatibility matrix, and the user
  confirms it**, as in 001 Task 10.
- **The applications:** TextEdit, Chrome, Safari, WeChat (the File Transfer
  chat), Terminal, a second terminal app, Messages and Notes.
  - The user agreed to Messages and Notes.
  - Notes: a temporary note only, with no screenshot, deleted afterwards.
  - Messages: a new message with no recipient.

**Applied.**
- The plan file is rewritten. The eval script now takes the IME's own request
  shape, and the README covers feature 002.
- In `progress.json`, Task 11's name, description, deliverables and
  acceptance items are changed. The acceptance items change by this decision.

### 001 Task 11: the eval results stay an artifact (2026-09-22)

The Task 11 revision listed `eval/results-translate.md` as a deliverable, but
`.gitignore` has kept `eval/results-*.md` out as runtime artifacts since the
harness was set up. The rule stands. The judged run, with its verdicts, is
copied into `docs/compat-matrix.md`, and the deliverable is dropped from the
ledger. The mistake was the agent's, in the revision.

### 001 Task 12 revised before start (2026-09-22)

**The user's decision.**
- **The recheck.** After the clean reinstall, the agent runs the core checks
  it can drive in TextEdit, K1–K12 from 001 and 002, and the user confirms
  them as a whole. The plan's "16 checks of Task 10 Step 6" is replaced: that
  table grew to 28 rows, and 002 added its own.
- **D2 stays open.** The plan asked to close D1–D3. D1 and D3 are closed, and
  D2 waits for the user.
- **The write-back.** The acceptance list's write-back item now names §10.2
  S1–S14 and §15, as the plan's table already did.

### 001 Task 12: wrap-up and write-back (2026-09-22)

**Verified.**
- `scripts/run_tests.sh` passes all 10 files.
- **A clean reinstall.** The IME's Lua and schema were removed, then
  `install.sh` ran twice. The first run installed everything, the second
  changed nothing, and the user config's hash was unchanged.
- **The core checks K1–K12,** driven by the agent in TextEdit, all passed.
  The user confirmed them as a whole.
  K6's closed-port test ran with the config restored afterwards to its exact
  hash.

**Written back.**
- `overview.md`: the status line.
- §5.3: the S2 outcome only.
- §10.2: the S1–S14 verdicts.
- §12: R11–R13 measured, R16 closed.
- §15.6: which F-rows the machine confirmed.
- §2: the backend (001 Task 11).

D1 and D3 were already closed. D2 and D6 stay open, for the user.

### D2 and D6 closed (2026-09-22)

The user's decisions, taken one at a time after each was explained with an
example.
- **D2 (focus loss commits the raw pinyin): accepted, as a documented cost.**
  - The alternative was to patch Squirrel's `commitComposition`, which commits
    `get_input`, so that it would commit the composed Chinese instead.
  - It was declined for its costs: a full Xcode, building and signing
    Squirrel, redoing the patch after every Squirrel update (the cask updates
    itself), and a fork to keep: Plan C′'s maintenance bill.
  - Instead, deal with the draft before switching away: Enter, Shift+Enter or
    Esc.
- **D6 (which schema a new session starts in): kept as librime does it,**
  the previously selected schema. The user uses translation often.
  Shift+Enter commits Chinese, and `Ctrl+Shift+T` switches back.
  - The cloud caveat stays in the README: an Enter meant as a newline would
    send the sentence out.

**Applied.**
- The open table now has no rows.
- architecture.md §5.1 and risks.md R11 record the outcomes.
- The status line in overview.md, testing.md's S12 note and the README's
  known limits are updated.

### Redeploy, not restart; one backend at a time (2026-09-22)

- **Measured by the agent (F28).** A redeploy (`Squirrel --reload`, or the
  input menu's Deploy) applies a config change and new Lua code with no
  `--quit`.
  - `install.sh`'s success notice no longer asks for a restart, since the
    script ends with a redeploy.
  - The config template and the README say "redeploy".
  - The spike report's claim that `--quit` is required carries a correction.
- **The user's decision.** One translation backend at a time: `translate`
  (the default) or a large language model the user configures. A hotkey to
  switch between backend profiles was offered and declined. The README gains
  "Using a large language model", with GLM as the tested example.
- **Corrected the same day.** The "declined" above was a misreading: the
  user meant one backend *in use* at a time, not one configured. A hotkey
  switch is feature 003; see the next entry.

### Feature 003 designed: a hotkey switches the backend (2026-09-22)

The user's request: the cloud where the network is good, the local
`translate` where it is not. Design in
[architecture.md §5.6](architecture.md) and [backend.md §9](backend.md).

- **The user's decisions**, taken one at a time:
  - a hotkey only, with no automatic fallback to local on a cloud failure
  - `Ctrl+Shift+B`
  - the choice is remembered across a redeploy or a restart
  - a notice on the switch **and** a marker on every cloud translation
- **The agent's calls, approved with the design:**
  - two slots, the local one unprefixed and backward compatible, the cloud
    one under a `cloud_` prefix
  - a cloud slot that fails the trust tier is dropped, never replaced by
    `translate`
  - the active slot is process-wide, not a Rime option, since options are
    per session (F14, F24)
  - the notice is Squirrel's own status message, through three switches
    hidden from the menu (F29)
  - the marker is decided by the URL, not by the slot's name
- **Left for later, by the user** ([features/README.md](../features/README.md),
  "Planned, not yet designed"):
  - 004, several backends at once with the results chosen by number,
    evaluated as feasible
  - a UI for configuring the backend

### Design review before feature 003 Task 1 (2026-09-22)

Read against librime 1.16.0 and Squirrel 1.1.2 (F29, added by this review). **The
skeleton holds**: every claim §5.6 makes about upstream traces to a source reading,
and none of the red lines is touched.

- **The notice is not seen while candidates are listed** (derivation, F29).
  Squirrel's panel discards a status message whenever it has candidates to
  draw.
  - With nothing typed, or a draft whose segments are all selected, the panel
    has neither candidates nor, under inline preedit, a preedit, so the notice
    shows.
  - With unselected pinyin it does not. The `☁` on the next translation still
    says which backend answered.
  - Settled by Task 6's R1 and R2.
- **The switch refreshes an open segment** (derivation, F20 and F29).
  `set_option` fires the option notifier, and with a composition open the
  engine refreshes what is not confirmed.
  - The input is untouched, so nothing is lost.
  - A candidate highlighted by hand in the open segment may fall back to the
    default, visibly, before any Enter.
  - Task 6's R2 records it.
- **The short label.** Squirrel's default `status_message_type` shows the
  abbreviated label: the first character unless `abbrev` is given. Without it,
  `云端翻译` and `云端未配置` would both show as `云`. Task 5 gives each notice
  switch an `abbrev` equal to its states (source reading, F29).
- **The hotkey's keysym.** Squirrel sends `B`, or `b` with Shift and Caps Lock
  both on. `decide` takes both (source reading, F29).
- **Not measured:**
  - that a Lua `set_option` from inside a key event reaches Squirrel's panel
    as a notice. The Shift tap's `ascii_mode` switch goes the same way, but
    whether its notice appeared was not recorded.
  - that the IME can write `~/Library/Rime/ime_translate.active` from inside
    Squirrel
  - Task 6's G1 and G6 settle both.

### D9 closed: a cloud slot needs `cloud_base_url` (2026-09-22)

- **Found by** 003 Task 1's review, green 2. A cloud slot with no
  `cloud_base_url` took the loopback default and passed the trust tier. Every
  cloud Enter would then fail against the local service with an unmarked
  `✗ 翻译失败`. Nothing left the machine.
- **The user's decision:** treat it as no cloud slot. The slot is dropped with
  a warning that names `cloud_base_url`, and `Ctrl+Shift+B` shows `云端未配置`.
- **Applied:**
  - [backend.md §9](backend.md) and [architecture.md §5.6](architecture.md)
  - `config.lua`
  - `tests/test_config.lua`: the D9 block; the fixtures with a cloud slot now
    name their `cloud_base_url`.
- **Plan.** Task 1's plan is not edited, since that task had closed; this
  entry is the record of the change.

### Layering and language (2026-09-19)

- All project documents and harness code switched to English. Three narrow
  exceptions stay Chinese because they are data rather than prose: the
  translation system prompt ([backend.md §7.4](backend.md)), the user-facing
  error strings shown in the candidate window
  ([backend.md §8.1](backend.md)), and Chinese test sentences.
- The single 553-line design document split into this `docs/design/` set, with
  section numbers retained as stable IDs. Cross references, the
  `scripts/design-section.sh` extractor and the design-context injection hook
  all keep working unchanged.
- `CLAUDE.md` reduced to an index plus the red lines. Everything else is loaded
  on demand, so session startup no longer pays for the full rule set.
