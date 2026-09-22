---
description: Start a task (defaults to the next unblocked one)
---

Load the `plan-execution` skill, then start the task named by $ARGUMENTS (or,
with no argument, whatever `./scripts/progress.sh next` returns).

1. `./scripts/progress.sh show <n>` — deps, deliverables, acceptance, plan anchor
2. Open the plan file `show <n>` printed and **read that task's steps through
   before touching anything**
3. `./scripts/progress.sh start <n>`
4. Follow the plan step by step

The plan's code is written out; use it rather than rewriting from memory. If the
task is marked `(manual)`, do not substitute your own judgement for the user's
observation — give commands and criteria one at a time and wait for what they
actually saw.
