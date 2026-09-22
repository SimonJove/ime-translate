---
description: Run the harness self-test (do the hooks actually block?)
---

Run `.claude/hooks/tests/run-hook-tests.sh` and report the result.

On any failure, fix the hook before doing anything else — a hook that never
fires is worse than no hook, because it supplies false confidence. Re-run the
suite after every hook change.
