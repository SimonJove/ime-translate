# Conventions and workflow

Loaded on demand, not every session. `CLAUDE.md` carries the red lines; this
carries everything else.

## Language

**English for every file**: code, comments, documentation, commit messages,
branch names, script output.

Three narrow exceptions, all of them *data* rather than project prose:

| Exception | Why |
|---|---|
| The translation system prompt (design §7.4) | It addresses a model translating Chinese input. Rewriting it in English would change the artifact under test. |
| User-facing `✗ …` error strings (design §8.1) | Shown in the candidate window of a Chinese IME, to a Chinese-reading user. |
| Chinese test sentences (design §10.4, spike fixtures) | They *are* the input under test. |

Chat replies to the user are Chinese; that is a separate thing from what lands
in files.

`checks_language` enforces this in both layers. Chinese is accepted only as
**data**, in one of three forms:

- a file whose whole job is holding it — `eval/`, `state.lua`, `config.lua`,
  `rime/*.schema.yaml`
- quoted inside a `.md` file, in a fenced code block or inline backticks
- inside a string literal in `tests/*.lua` — the test data the table above
  allows. A comment in a test file is still prose and still refused, even when
  it quotes Chinese. Product code under `rime/lua/` gets no such allowance.

So when documentation quotes one of the product's own Chinese strings, put it in
backticks: `` `✗ 翻译超时` ``. That is also semantically right — it is data being
quoted, not prose. A Chinese comment or a Chinese sentence in running text is
refused.

## Commits

Format `<type>: <summary>`, type ∈ `feat | fix | docs | test | chore |
refactor`. First line ≤ 72 characters; detail goes in the body.
`.githooks/commit-msg` enforces both.

No `Co-Authored-By` trailer and no "Generated with …" line, in commits or in
pull requests: the history names its human author only, and no tool appears
among the repository's contributors (the user's decision, 2026-09-22).
`.githooks/commit-msg` refuses both.

Never commit or push unprompted. The user decides when.

`guard-push.sh` makes the push half mechanical: an agent's `git push` is refused
unless the command carries `# authorized-by-user`. `git commit` is deliberately
**not** gated — this project works directly on main and the plan ends every task
with a commit, so a commit gate would block the normal workflow. Publishing is
the irreversible step; a local commit is not. The guard is dormant until a
remote exists.

## Tests

- One module: `lua tests/test_<module>.lua`
- Everything: `scripts/run_tests.sh` (created by Task 2)
- Harness itself: `.claude/hooks/tests/run-hook-tests.sh` (Claude layer) and
  `.githooks/tests/run-githook-tests.sh` (git layer) — run both before and after
  touching any hook. `pre-commit` forces both anyway.
  `./scripts/setup-harness.sh --check` runs everything and reports in one pass.

Zero external Lua dependencies (no busted, no cjson). Lua 5.4.

## The implementation loop

Full procedure in the `plan-execution` skill. In short:

```bash
./scripts/progress.sh next          # what is unblocked
./scripts/progress.sh show <n>      # deps, deliverables, acceptance, plan anchor
./scripts/progress.sh start <n>     # records the baseline commit
#   … follow the plan file that `show` printed, step by step …
./scripts/progress.sh done <n> <hash>
```

Entry points: `/task-status`, `/task-start`, `/task-done`, `/hook-test`,
`/design-review`.

**A task can be blocked by the design, not only by another task.** A row in the
open table of `docs/design/decisions.md` names the tasks it blocks, and
`progress.sh start` refuses them. `./scripts/progress.sh decisions` lists what
is open; closing one is the user's call.

**Not all work is a feature.** A feature adds a capability and gets a directory
under `docs/features/` with a plan and a ledger. Something wrong whose cause is
unknown is an `/issue` (single file, `Status` may end at `wontfix`); something
wrong and urgent is a `/hotfix` (single file, fix first, and Prevention must
name which enforcement layer should have caught it).

**Acceptance items must all pass before a task is marked done.** If one cannot,
say where it is stuck — do not lower the bar and do not edit the acceptance
list.

**Every task passes review before it is marked done** (`/task-done` step 2):
the `task-reviewer` agent, 🔴 cleared to zero. Documentation-only tasks skip it.

## Harness

Four layers, ordered by when they act. Each catches what the one before it
cannot see.

**0 — before anything is built: the design against reality.**

| Piece | Role |
|---|---|
| `.claude/skills/design-review/SKILL.md` + `/design-review` | Reads upstream source for every claim the design makes about it; defines the evidence labels (source reading / derivation / unverified / measured) |
| `docs/design/decisions.md`, "Open decisions" + `scripts/open-decisions.sh` | What is not decided yet, and which tasks it blocks. The script is the table's only reader |

**1 — before an edit applies (Claude only).**

| Piece | Role |
|---|---|
| `.claude/hooks/lib/checks.sh` | The **only** implementation of the hard checks: spike gate, Lua invariants, secrets, language |
| `.claude/hooks/{gate-spike,check-lua-invariants,check-secrets,check-language}.sh` | Thin wrappers around it. `check-language` rebuilds the post-edit file, so an Edit inside a fenced block is judged as fenced |
| `.claude/hooks/guard-push.sh` | Refuses an unauthorised `git push` (dormant: no remote yet) |
| `.claude/hooks/inject-design-context.sh` | Injects the governing design sections when you edit a file, once per session — open-finding notes included |
| `.claude/hooks/session-status.sh` | One line at session start: progress, gate, open decisions; shouts if `core.hooksPath` has drifted and the git layer has gone inert |

**2 — at git (hand edits and scripted edits too).**

| Piece | Role |
|---|---|
| `.githooks/{pre-commit,commit-msg}` | The same `checks.sh`, over staged content; commit message format |
| `.githooks/reference-transaction` | Refuses deletion of `main`. `git branch -d/-D` fires no ordinary hook, and this repo has no remote — `main` is the only copy. Override: `ALLOW_PROTECTED_BRANCH_DELETE=1` |

**3 — before a task closes: semantics.**

| Piece | Role |
|---|---|
| `.claude/agents/task-reviewer.md` + `.claude/skills/task-review/SKILL.md` | The pre-done review gate; output to the feature's `review-log.md` |
| `scripts/progress.sh` | The only writer of a ledger's state; refuses a task with unmet dependencies or a blocking open decision |

**Proving the harness itself works.**

| Piece | Role |
|---|---|
| `.claude/hooks/tests/run-hook-tests.sh` | Asserts over layer 1 and the open-decision gate, in sandboxes |
| `.githooks/tests/run-githook-tests.sh` | Asserts over layer 2, in disposable sandbox repos |
| `scripts/setup-harness.sh` | One-off install (`core.hooksPath`) + health check; `--check` runs both suites and prints the live assertion counts, which is why none are written down here |
| `.claude/worktree-context.md` | Read before dispatching any worktree sub-task |

The check logic exists once and is sourced by both layers. Writing it twice
guarantees drift, and drift always makes the git side the looser one.

Layers 1–3 guard the implementation against the design. Layer 0 is the only one
that guards the design against upstream, and it is a procedure, not a hook:
nothing mechanical can read librime for you. What *is* mechanical is its output —
an open decision really does stop the task that would build on it.

## Real-machine work

Tasks 1, 10 and 11 are marked `manual` in `progress.json`. They need a person
at the machine installing the IME, adding the input source in System Settings,
and **looking at what actually appears in the input box**. An agent supplies
commands, reads logs and records results; it cannot do the observing.

Never write "per the plan it should be X" as a measured result. Vendor
performance claims, estimated latency, and this project's own measurements are
recorded separately (design §12).
