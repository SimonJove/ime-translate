# Worktree sub-task context — ime-translate

Project appendix for the global `worktree-subtask` skill. **Content only** — the
procedure (brief structure, the two-level gate, authorization red lines) lives
in the skill.

## Coordinates

- **Base / merge target**: this project works directly on `main`; there is no
  campaign branch. **So before dispatching any worktree, create a campaign
  branch and confirm its name with the user** — the global rule forbids
  dispatching while the primary checkout sits on the trunk, and a trunk
  branch-guard will block the parent session for the rest of the campaign.
- **Branch naming**: `feat/task-<n>-<slug>`, e.g. `feat/task-6-backend-adapters`
- **Worktrees**: `.claude/worktrees/<slug>/` (already gitignored)
- **Working language**: English for everything — briefs, reports, code,
  comments, commit messages, documentation. Chat replies to the user are
  Chinese; that is separate from what lands in files.
- **Commits**: `<type>: <summary>`, subject ≤ 72 chars. `commit-msg` enforces it.

## Whether anything can run in parallel depends on the gate

**Before S1/S3/S11 pass, there is no parallel implementation work at all.** Task 1
is a real-machine spike: one person, one machine, so a worktree buys nothing —
and `gate-spike.sh` will refuse every write to `rime/` and `tests/` inside the
worktree anyway (the hook reads that worktree's own copy of the ledger).

Once the gate passes, **Tasks 4 / 5 / 7 / 8** can run in parallel (pure Lua,
headless, mutually independent). Task 2→3 is serial, Task 6 waits on 2/3/4/5,
and everything from Task 9 on is serial because it needs the real machine. Run
`./scripts/progress.sh next` before dispatching to see what is genuinely
unblocked.

Tasks 1 / 10 / 11 are marked `manual`: they need **a human looking at the input
box**. Do not dispatch them to a worktree.

## Environment traps

- **Real-machine IME state is global.** There is exactly one `~/Library/Rime/`
  and one Squirrel process. Two worktrees installing schemas and hitting
  "Redeploy" at the same time overwrite each other, and the symptom is "my
  change didn't take effect" — the hardest kind to diagnose. **Only one worktree
  may touch the real machine at a time.**
- **Backend ports are global too**: apfel `:11434`, translate `:8989`. Running
  benchmarks in parallel corrupts the latency numbers.
- **Do not touch the Keychain.** `security add/find-generic-password` is in
  `settings.json`'s deny list. The user stores the key once, themselves.
- The development machine: macOS on Apple silicon, Lua 5.4.8, jq and python3 present.

## Campaign-goal facts

Read by `/goal-compose` before it writes a campaign goal. Project facts come
from here, never from memory.

### There is exactly one campaign window

This project is not a corpus to sweep; it is one plan with a life-or-death gate
in front of it. A campaign is only meaningful for **Tasks 2–9**, and only once
`./scripts/progress.sh features` reports `gate S1/S3/S11: pass`.

| Phase | Campaign? |
|---|---|
| Task 1 | **No.** A real-machine spike: install the IME, watch an input box. One person, one machine. An autonomous loop here has a motive to route around the gate, which is the one thing it must not do |
| Tasks 2–9 | **Yes** — pure headless Lua, `lua tests/test_*.lua` is the whole verification |
| Tasks 10–11 | **No.** Real machine again: the 16 smoke checks and the blind eval are observation, not computation |
| Task 12 | No. Clean reinstall plus writing conclusions back into `design/` |

Composing a goal that spans a `manual` task is a compose-time error. Check the
`manual` flag with `./scripts/progress.sh show <n>`.

### Units, and how big each is

The unit is a **task**, not a file. Sizes, so batches can be planned:

| Unit | Plan file lines | Notes |
|---|---|---|
| 2 scaffolding + json encode | 104 | must land before 3 |
| 3 json decode | 186 | |
| 4 state | 111 | independent |
| 5 config | 208 | independent |
| 6 backend adapters | 279 | largest; three adapters × eight error codes |
| 7 session | 189 | independent |
| 8 decide | 163 | independent |
| 9 glue layer | 259 | consumes 5/6/7/8 |

**One task per worktree.** Do not batch two tasks into one dispatch: each has
its own acceptance list and its own review round, and a shared branch makes the
review diff span both.

### Hard order, with the reason

```
2 → 3          json.decode extends the module json.escape creates
4, 5, 7, 8     independent of each other; 5 needs 2 (json), 7 and 8 need 4 (state)
2,3,4,5 → 6    backend consumes json, state constants and settings
5,6,7,8 → 9    the glue layer wires all four together
```

Reason, not preference: each arrow is a `require` that will not resolve
otherwise. `./scripts/progress.sh next` computes this from `dependsOn` — use it
rather than re-deriving the order by hand.

### External dependencies and their skip cascades

| Dependency | Needed by | If missing |
|---|---|---|
| `lua` 5.4 | every unit | Nothing runs. Stop, do not dispatch |
| apfel on `:11434` | Task 1 S8 only | S8 halves → only `translate` gets a latency number → the default-backend decision in Task 11 has one side |
| `translate` on `:8989` | Task 1 S8, Task 11 | Needs a one-off zh→en model download through System Settings, which no script can drive. **Missing → S8 zeroes out → the Task 11 blind eval cannot run → the default backend stays undecided.** That is a decision left open, not a failure to report |
| Squirrel installed + input source added | Tasks 1, 10, 11 | Every real-machine unit zeroes out |

Tasks 2–9 need **none** of these: they mock `io.popen` and never touch a
backend. That is precisely why they are the campaign window.

**The ports are global.** apfel and `translate` bind one port each on one
machine. Two worktrees benchmarking at once produce latency numbers that are
quietly wrong rather than obviously broken — the worst failure shape. Any unit
that measures latency runs alone, in the primary checkout.

### What "done" means for a unit

Never the sub-task's own word for it. A unit is done when:

1. every acceptance item from `./scripts/progress.sh show <n>` has **actual
   output** pasted, not "should be fine";
2. `scripts/run_tests.sh` is green in full, not just that unit's file;
3. the `task-reviewer` gate has run with **zero 🔴** remaining;
4. the parent — not the sub-task — has written `progress.sh done <n> <hash>`.

A sub-task reports; the parent verifies and records. `gwt-done` marks a branch
ready for gating, it does not mark the task done.

### Issue records

A defect found mid-campaign that is **not** this unit's job goes to
`docs/issues/<YYYYMMDD>-<slug>.md` (template in `docs/issues/README.md`,
`Status` starts at `investigating`). Do not fix it inside an unrelated unit —
that makes the review diff span two concerns and hides the second one.

If the defect is in the **plan itself** — a step that cannot work as written —
that is not an issue. Report it and stop: the plan is immutable, and changing
it is the user's call.

### Pace

At most **3 worktrees** at once. The ceiling is not machine capacity; it is that
every returning branch needs a review round in the parent, and four pending
reviews is where the parent stops reading diffs properly and starts skimming.

Refill a free slot as soon as one gates through. Never skip a gate to keep
slots full.

## Read-only paths

A sub-task must **not** change these. To change one, report back first.

| Path | Why |
|---|---|
| `docs/design/` | The source of truth. Section numbers are cited by the plan; renumbering scatters every cross reference. Written back only in Task 12 |
| the feature's `plan/` | The immutable "how". Differing from it is allowed, but say so in the report rather than quietly editing the plan |
| the feature's `progress.json` | The parent session's ledger. Sub-tasks report results; the parent writes |
| `.claude/hooks/` | Changing the harness is not a sub-task's job |

## What to bring back

- Which files changed, and why
- **Each acceptance item's actual output** (the list from
  `./scripts/progress.sh show <n>`), not "should be fine"
- The full result of `scripts/run_tests.sh`
- Every deviation from the feature's `plan/`, with a reason
- The branch name

Then run the dispatch tooling's `gwt-done` and stop. **Landing —
commit, rebase, merge, push, removing the worktree, deleting the branch — always
needs explicit authorization from the user**; the default is "keep the branch,
do not land".
