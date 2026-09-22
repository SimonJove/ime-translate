---
description: Open an investigation for something wrong whose cause is unknown
---

Open an issue for $ARGUMENTS.

1. Create `docs/issues/<YYYYMMDD>-<slug>.md` from the template in
   [`docs/issues/README.md`](../../docs/issues/README.md). Status starts at
   `investigating`.
2. Fill **Symptom** from what the user actually reports — exact input, exact
   output, which application, whether it reproduces. Ask for what is missing
   rather than inventing it; "sometimes it eats a sentence" is a starting
   point, not a symptom.
3. Investigate. Record each step and what it ruled in or out, with `file:line`
   and log excerpts. **Write down the dead ends too.**
4. Update Status as the picture changes: `investigating` → `identified` →
   `resolved` | `wontfix`.
5. If a fix is needed, make it on main and commit normally. If the cause turns
   out to be a missing capability, close with that finding and propose a
   feature instead.

`wontfix` is a legitimate ending. Recording why is the point.

If this is urgent and the cause is already clear, it is a hotfix — use
`/hotfix`.
