---
name: plan-execution
description: The implementation loop — start a task, verify it, review it, close it, with state in the feature's progress.json. Use when starting a task, closing a finished one, or asking "where are we" / "what's next".
---

# Implementation loop

Three documents, distinct jobs. **Do not blur them.**

| File | Nature | Who changes it |
|---|---|---|
| `docs/design/` | Why it is this way. Section numbers are stable IDs cited by the plan | Only in Task 12, or when the design genuinely changes. A choice that should change but is undecided is an **open decision**, not an edit |
| the feature's `plan/` | How to build it. Steps and code per task. **Immutable once that task has started** | Before a task starts: an error in the plan may be fixed, logged in `design/decisions.md`. After: never — deviations go in the task report |
| the feature's `progress.json` | Where we are. **The mutable state** | State fields only through `scripts/progress.sh`; definition fields (acceptance, the gate) only by the user's decision |

"The feature" above is whichever directory under `docs/features/` you are
working in — `./scripts/progress.sh show <n>` prints the exact plan file, so
paths are never guessed.

`progress.json` is the single source of truth for execution state. **Always go
through `scripts/progress.sh`; never hand-write jq** — hand-rolled jq easily
overwrites the whole `tasks` array or writes local time into a UTC field.

## Starting a task

```bash
./scripts/progress.sh next        # what is unblocked
./scripts/progress.sh show <n>    # deps, deliverables, acceptance, plan anchor
./scripts/progress.sh start <n>   # records the baseline commit for review
```

Then open the plan file `show <n>` printed and
**follow the steps in order**. Each `- [ ]` is a 2–5 minute action, and the code
in the steps is usable as written — do not rewrite it from memory.

`start` refuses a task whose dependencies are unmet. Skipping one must be the
user's explicit decision: set that task's `status` to `skipped` and say why.

`start` also refuses a task that an **open design decision** blocks
(`./scripts/progress.sh decisions`). That means the part of the design the task
builds on is not settled — usually because a spike result is still owed. Do not
route around it: no `ALLOW_OPEN_DECISION=1` on your own initiative, no starting
"just the parts that don't depend on it". Tell the user which decision is in the
way and what evidence it is waiting for. Closing it is theirs.

When a design section you are injected with carries an **open-finding note**,
the note outranks the section's body: the body is what was written, the note is
what is known to be wrong with it.

## Closing a task

Five things, in order, none optional:

1. **Run the acceptance items.** Every line `show <n>` printed needs evidence,
   not "should be fine". One module: `lua tests/test_<module>.lua`. Everything:
   `scripts/run_tests.sh`.
2. **Pass review.** Dispatch the `task-reviewer` agent (its procedure is the
   `task-review` skill; it fetches `./scripts/progress.sh diffrange <n>`
   itself).
   - 🔴 must reach zero: fix them, or record the user's explicit acceptance in
     the feature's `review-log.md`
   - 🟡 fix, or defer with a one-line reason
   - Re-run the review until no 🔴 remain. **With a 🔴 open, do not proceed to
     step 3.**
   - Documentation-only tasks (diff touches only `docs/` or `*.md`) skip this.

   This gate catches what unit tests cannot: text-eating paths, the commit exit
   being circumvented, a missing invalidation check, state sliding back into a
   module singleton, and **tests written so they can never fail**.
3. **Commit.** `<type>: <summary>`, first line ≤ 72 chars
   (`.githooks/commit-msg` enforces it).
4. **Record.** `./scripts/progress.sh done <n> <commit hash>`
5. **Report.** What changed, each acceptance item's actual output, what review
   found, what the next task is.

**No task is marked done with an acceptance item unmet.** If one cannot pass,
say where it is stuck and what is missing — do not lower the bar and do not
rewrite the acceptance list.

## Two gates

**Gate one: S1/S3/S11 (Task 1).** Until the spike concludes, every write to
`rime/` and `tests/` is refused by `.claude/hooks/gate-spike.sh`. This is design
§3.5's ratchet, enforced mechanically.

```bash
./scripts/progress.sh gate pass   # S1, S3 and S11 all hold
./scripts/progress.sh gate fail   # any one of them is falsified
```

`fail` on **S1 or S3** means Plan A′ does not exist: stop implementing, return
to design, evaluate Plan B′ (Lua-owned draft) first. Do not jump to C′ (fork
Squirrel), and do not quietly amend the design to keep going. `fail` on **S11**
sends design §6.1–§6.2 back to design review before any implementation
continues; A′ itself may still stand (decision D3, design §13).

The gate passing proves the foundations, not the product. The spike also carries
S12–S14, which are acceptance items rather than gate items. **If S13 showed
Enter reaching the application at 1.5 s, report to the user before running
`gate pass`** even when S1/S3/S11 all hold — the synchronous model itself is
then in question (Task 1 Step 11).

**Gate two: the real-machine smoke checks (Task 10, Step 6).** Task 11 does not start
until they pass.

## What an agent cannot do

Tasks marked `(manual)` by `show` — 1, 10, 11 — need a person at a real machine
installing the IME, adding the input source in System Settings, and **looking at
what actually appears in the input box** in TextEdit, WeChat, a terminal. An
agent can give commands, read logs and record results; it **cannot do the
observing**, and must never write "per the plan it should be X" as a measured
result.

The shape that works: the agent gives commands and criteria one at a time → the
user runs them and reports what they saw → the agent records it.

## Project red lines

See `CLAUDE.md`. They are enforced in three layers: `.claude/hooks/` blocks
before an edit applies, `.githooks/pre-commit` blocks at commit time (catching
hand edits too), and the review gate inspects semantics before a task closes.
**The check logic exists exactly once**, in `.claude/hooks/lib/checks.sh`, shared
by the first two layers.

Run `.claude/hooks/tests/run-hook-tests.sh` before and after touching any hook
(`pre-commit` forces it anyway).

## The design comes to you

Editing `backend.lua` injects §7; `processor.lua` injects §5.2/§6.2/§6.3;
`session.lua` injects §6.1 — once per session per file, **before the edit
applies**.

So do not write constants from memory. To look up anything else:
`./scripts/design-section.sh 8.2`.
