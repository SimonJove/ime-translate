# Documentation

Navigation hub. Find your question below rather than browsing directories.

## Where to look

| Question | Document |
|---|---|
| What is this, in 30 seconds? What are the invariants? | [`design/overview.md`](design/overview.md) |
| Is X in scope? What did we decide not to build? | [`design/requirements.md`](design/requirements.md) — §1–§2 |
| How does a keystroke become English? Who owns the draft? | [`design/architecture.md`](design/architecture.md) — §3–§6 |
| How do I call a backend? What are the error codes? What config keys exist? | [`design/backend.md`](design/backend.md) — §7–§9 |
| What does the spike verify? What must the compat matrix cover? | [`design/testing.md`](design/testing.md) — §10 |
| How do I install it? What could go wrong? | [`design/risks.md`](design/risks.md) — §11–§12 |
| Why is it built this way and not another? | [`design/decisions.md`](design/decisions.md) — §13 |
| Which backend should be the default, and on what evidence? | [`design/evidence.md`](design/evidence.md) — §14 |
| What does librime / Squirrel really do here? Is that assumption read from source or guessed? | [`design/upstream.md`](design/upstream.md) — §15 |
| What is still undecided? | [`design/decisions.md`](design/decisions.md) — the open table, D1–D3 |
| What features exist, and what state is each in? | [`features/`](features/README.md) — `./scripts/progress.sh features` |
| What do I build next, step by step? | [`features/001-zh-en-ime/plan/`](features/001-zh-en-ime/plan/README.md) — 12 tasks |
| Where are we? What is unblocked? | `./scripts/progress.sh status` |
| What did review find on a task? | that feature's `review-log.md` |
| Something is broken and I don't know why | [`issues/`](issues/README.md) — `/issue` |
| Something is broken and it's urgent | [`hotfixes/`](hotfixes/README.md) — `/hotfix` |
| Did S1/S3/S11 hold? Which versions were they measured on? | `spike-report.md` (created by Task 1) |
| Did the installed IME pass on the real machine? | [`smoke-report.md`](smoke-report.md) (Task 10) |
| Which applications actually work? | `compat-matrix.md` (created by Task 11) |
| How do I work in this repo — conventions, harness, gates? | [`../.claude/rules/core.md`](../.claude/rules/core.md) |
| How do I run and use the IME? | `../README.md` (created by Task 11) |

One section, not a whole file: `./scripts/design-section.sh 6.2`. Editing a
governed file injects its sections automatically
(`.claude/hooks/inject-design-context.sh`), once per session per file, so you
rarely need to fetch design text by hand.

## The three layers

- **Design says why** (`design/`). Change it only when the design actually
  changes — normally that means Task 12, writing the spike's verdicts back. A
  choice that *should* change but has not been decided is a row in the open
  table of [`design/decisions.md`](design/decisions.md), not an edit: the
  `design-review` skill says how.
- **Plan says how** (`features/<id>/plan/`). A task's plan file is **immutable
  from the moment that task starts**: an implementation may deviate, but the
  deviation is explained in the task report, never quietly patched into the
  plan. Before it starts, an error *in the plan* may be fixed, with an entry in
  `design/decisions.md` saying what and why.
- **Progress says where** (`features/<id>/progress.json`). Its *state* fields —
  status, timestamps, commits, the gate verdict — are never hand-edited;
  `scripts/progress.sh` is their only writer. Its *definition* fields — tasks,
  acceptance lists, what the gate is — are authored with the plan and change
  only by the user's decision ([`features/README.md`](features/README.md)).

Work that is not a feature has its own shape: an [issue](issues/README.md) when
something is wrong and the cause is unknown, a [hotfix](hotfixes/README.md) when
it is wrong and urgent. Both are single files, neither has a plan, and a hotfix
must name which enforcement layer should have caught it.

## Conventions

- **Section numbers are stable IDs.** `§X.Y` headings inside `design/` are cited
  by every feature's `plan/` and resolved across files by
  `scripts/design-section.sh`. Renumber
  a section and you scatter every reference; splitting or moving a *file* is
  safe.
- **One design file per concern**, kebab-case, under `design/`. A new concern
  gets a new file plus a row in the table above and in
  [`design/overview.md`](design/overview.md) — not a new top-level directory.
- **One directory per feature**, `features/<NNN>-<slug>/`, holding `plan/`,
  `progress.json` and `review-log.md`. The same shape for every feature, so
  `scripts/progress.sh` never special-cases one. The product design stays in
  `design/` and is shared — a feature amends a `§` there rather than forking it.
- **One plan file per task**, `plan/task-NN-<slug>.md`, listed in that feature's
  `plan/README.md` and pointed at by the task's `planAnchor` in its
  `progress.json`. All three move together.
- **Issues and hotfixes are single files**, `<YYYYMMDD>-<slug>.md`. No
  directories: neither grows a second document.
- **Artifacts of a run** — the spike report, the compat matrix, eval results —
  are records of a moment, not design. They live at the top of `docs/`, named
  for what they record. Their *conclusions* get written back into `design/`
  (Task 12); the artifact itself stays as the evidence.
- **Generated output is not committed**: `eval/results-*.md` is gitignored. The
  decision it produced belongs in `design/`, the raw run does not.
- **English everywhere**, with Chinese permitted only as quoted data, in a code
  block or backticks. `checks_language` enforces it; the rule and its three
  exceptions are in [`../.claude/rules/core.md`](../.claude/rules/core.md).
- **No `archive/` yet.** This project is 12 tasks; nothing has been superseded
  that git history does not hold. Add one when a real batch of documents is
  retired, not in anticipation.
