---
description: Close a task: acceptance, review gate, commit, record, report
---

Load the `plan-execution` skill and close the task named by $ARGUMENTS (or the
one currently `in_progress`).

1. `./scripts/progress.sh show <n>` for the acceptance items, and **produce
   evidence for each** — `lua tests/test_<module>.lua` per module,
   `scripts/run_tests.sh` for everything. If one does not pass, stop and say
   where it is stuck: do not mark done, do not edit the acceptance list.
2. **Review gate**: dispatch the `task-reviewer` agent (it fetches `diffrange`
   itself).
   - 🔴 must reach zero: fix, or record the user's explicit acceptance in
     the feature's `review-log.md`
   - 🟡 fix, or defer with a one-line reason
   - Re-run until no 🔴 remain
   - **With a 🔴 open, do not proceed to step 3**
   Documentation-only tasks (diff touches only `docs/` or `*.md`) skip this.
3. `git add` + commit, `<type>: <summary>`, first line ≤ 72 chars
4. `./scripts/progress.sh done <n> <commit hash>`
5. Report: what changed, each acceptance item's actual output, what review
   found, what the next task is
