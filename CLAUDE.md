# ime-translate

Chinese→English translation IME for macOS, on Rime/Squirrel: type Chinese, press
Enter, English commits to the application. Personal use.

**Documentation only, no code yet.** Task 1's S1, S3 and S11 gate the tree
until they conclude; S1/S3 decide whether the plan exists at all.

## Where to look

| Need | Read |
|---|---|
| The model, the invariants, the gate | [`docs/design/overview.md`](docs/design/overview.md) |
| Anything else about the design | [`docs/README.md`](docs/README.md) — the index |
| What to build, step by step | [`docs/features/`](docs/features/README.md) — 001 is v1 |
| Where we are | `./scripts/progress.sh status` |
| What is still undecided, and what it blocks | `./scripts/progress.sh decisions` |
| What librime / Squirrel really do | [`docs/design/upstream.md`](docs/design/upstream.md) — read from source, not assumed |
| Conventions, workflow, harness | [`.claude/rules/core.md`](.claude/rules/core.md) |

One section beats a whole file: `./scripts/design-section.sh 6.2`. The sections
governing a file are injected automatically when you edit it.

## What the tools will not catch

Five red lines are enforced mechanically (`.claude/hooks/` before an edit,
`.githooks/pre-commit` at commit time) — when one blocks you, its message says
what to do. They are listed in
[`docs/design/overview.md`](docs/design/overview.md); do not rely on memory for
their detail.

These three have no check behind them, so they live here:

- **Never eat text** (design §6.3) — before any `ctx:clear()`, a
  `commit_text()` must already have committed the Chinese draft or the English
  translation. Every path, including error branches and early returns.
- **Send is always manual** (design §2) — the IME never triggers send itself.
- **A human observes the real machine.** Tasks 1, 10 and 11 need someone
  watching what actually appears in an input box. Supply commands and criteria;
  never write "per the plan it should be X" as a measured result.

## Working rules

- **English** in every file. Chinese only as quoted data — see `rules/core.md`.
- Not every job is a feature: `/issue` when the cause is unknown, `/hotfix` when
  it is urgent. Neither gets a plan.
- A claim about upstream behaviour is a **source reading**, a **derivation** or
  **unverified** — say which. Only a person at the machine makes it **measured**.
  A design choice that should change is an open decision, not an edit
  (`/design-review`).
- Never commit or push unprompted. A `git push` also needs
  `# authorized-by-user`, added only after the user says yes.
