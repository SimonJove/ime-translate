# Features

A feature is one user-visible capability, built as a numbered work package.
Every feature has the same shape, so the machinery does not care which one you
are working on:

```
docs/features/<NNN>-<slug>/
  plan/          README.md (overview, constraints) + one file per task
  progress.json  the tasks, their acceptance, and the gate
  review-log.md  what review found, round by round
```

The product design is **not** per feature. It lives in
[`../design/`](../design/overview.md) with stable `§X.Y` numbering, shared by
everything. A feature that changes behaviour amends the relevant section there
rather than starting a private copy — otherwise two features would each hold
half of the key table.

## Two halves of a ledger

`progress.json` holds two different kinds of thing, with different owners:

| Half | Fields | Who writes it |
|---|---|---|
| **Definition** | the task list, `dependsOn`, `deliverables`, each `acceptance` list, `gate.id` and `gate.description` | Authored by hand with the plan. Afterwards it changes **only by the user's decision**, as a reviewed edit with an entry in [`../design/decisions.md`](../design/decisions.md). An agent never rewrites an acceptance list to make a task closable |
| **State** | every `status`, `startedAt`, `completedAt`, `baseCommit`, `commits`, `gate.status`, `gate.verifiedAt` | `scripts/progress.sh` and nothing else — hand-rolled jq overwrites arrays and writes local time into UTC fields |

"Never hand-edit progress.json" means the state half. When a design review
wants the definition changed — a new gate item, a longer acceptance list — it
opens a decision ([`../design/decisions.md`](../design/decisions.md), "Open
decisions") instead of editing.

A task can also be held back by the design rather than by another task: a row in
that open table names the tasks it blocks, and `progress.sh start` refuses them
until the row is gone. `./scripts/progress.sh decisions` lists what is open.

## Index

| # | Feature | State | Notes |
|---|---|---|---|
| 001 | [`001-zh-en-ime`](001-zh-en-ime/plan/README.md) | done, 12/12 | v1: type Chinese, commit English. Gated on the S1/S3/S11 spike (passed) |
| 002 | [`002-mixed-input`](002-mixed-input/plan/README.md) | done, 7/7 | A Shift tap switches Chinese and English inside a draft; Enter translates the mixed sentence |
| 003 | [`003-backend-switch`](003-backend-switch/plan/README.md) | done, 6/6 | `Ctrl+Shift+B` switches translation between a local and a cloud backend |
| 004 | [`004-option-tap`](004-option-tap/plan/README.md) | done, 2/2 | A lone Right Option tap replaces `Ctrl+Shift+B`, so the switch works with nothing typed |
| 005 | [`005-reliable-enter`](005-reliable-enter/plan/README.md) | planned, 0/5 | A failed cloud falls back to local; Enter retries after an error; a translation cache; `translate` keeps URLs |

`./scripts/progress.sh features` prints this from the ledgers, which is the
authority; this table is for reading.

### Planned, not yet designed

Requirements the user has asked for, recorded before any design exists. Each
becomes a numbered feature, with its own design pass, when its turn comes.

| Order | Requirement | Asked | Notes so far |
|---|---|---|---|
| 1 | **Several backends at once, results chosen by number** (the next free number; first called 004): each Enter asks several backends, and the translations show numbered; a digit commits that one | 2026-09-22 | Evaluated as feasible, after 003, reusing its slots. The results go into the prompt, and the processor intercepts the digits: a translation must not become a Rime candidate (upstream F5, design §6.4 and D1). The requests run in parallel, so the freeze is the slowest backend's timeout. Every sentence goes to every cloud backend in the set. Whether a long prompt with several sentences shows in full is unmeasured. In the result phase, digits 1..N stop reaching the draft |
| 2 | **A UI for configuring the translation backend**, so the user never edits `ime_translate.yaml` by hand | 2026-09-22 | A later requirement; no implementation is scheduled yet. Whatever the UI is, it must keep these: the API key goes only to the Keychain, never to a file (design §7.3); the flat `ime_translate.yaml` stays the one source the IME reads; a change still takes effect through a redeploy (upstream F28), unless the design changes that; and a remote backend still needs the explicit `allow_remote` opt-in (design §7.2) |

## Working on one

```bash
./scripts/progress.sh features          # every feature and its state
./scripts/progress.sh status [id]       # one feature's tasks
./scripts/progress.sh next [id]         # what is unblocked
./scripts/progress.sh start <n> [id]
./scripts/progress.sh done <n> <hash>
./scripts/progress.sh decisions         # open design decisions, and what they block
```

`[id]` is a directory name or any unambiguous prefix (`001`, `zh-en`). With no
id, `PROGRESS_FEATURE=<id>` is used if set, and otherwise the single feature
that is still open. If several are open, the command names them instead of
guessing — writing a task update into the wrong ledger is not a mistake worth
risking for one saved argument. `done` and `gate` have no `[id]` slot, so with
two features open, `PROGRESS_FEATURE` is how to name one for them.

## Starting a new one

1. Pick the next number and a slug: `docs/features/002-<slug>/`.
2. Decide what changes in [`../design/`](../design/overview.md) and amend it
   there first. If nothing changes, this is probably an issue, not a feature.
3. Write `plan/README.md` (goal, task overview, constraints) and one file per
   task, following 001's shape.
4. Write `progress.json`: tasks with `dependsOn`, `deliverables`, per-task
   `acceptance`, and a `gate` only if something really is life-or-death.
5. Add a row to the index above.

**Not everything is a feature.** Something broken with an unknown cause is an
[issue](../issues/); something broken and urgent is a
[hotfix](../hotfixes/). Both are single files and neither needs a plan.
