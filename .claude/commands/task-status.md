---
description: Show implementation status: gate, the 12 tasks, what is unblocked
---

Run `./scripts/progress.sh status` and `./scripts/progress.sh next`, and report
the result.

If a task is `in_progress`, also run `./scripts/progress.sh show <n>` and check
it against `git status` / `git log --oneline -5`, then say which acceptance item
it is stuck on.

If $ARGUMENTS is a task number, show just that task instead (`show <n>`).
