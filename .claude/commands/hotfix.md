---
description: Fix something urgently broken, then record the postmortem
---

Handle a hotfix for $ARGUMENTS.

1. **Fix it first.** Do not break this into tasks; urgency is why the shape
   exists.
2. Create `docs/hotfixes/<YYYYMMDD>-<slug>.md` from the template in
   [`docs/hotfixes/README.md`](../../docs/hotfixes/README.md) and fill
   Incident, Root cause, Fix, Verification.
3. **Prevention is the part that matters.** Answer the actual question: which
   of the three layers should have caught this, and why did it not?
   - a hook rule is missing → add the check *and* its assertions to the suite
   - the review rubric has no dimension for it → add one to `task-review`
   - no layer could have → it is a design defect; fix `docs/design/` and name
     the `§`
   "Be more careful" is not an answer. If nothing can catch it, say so
   explicitly and say why.
4. Commit. Severity and Prevention must both be filled before you do.

For this project, **critical** means a red line was crossed: text was eaten, a
secret escaped, or the wrong content committed to an application.
