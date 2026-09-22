# Hotfixes

Something is broken, the cause is known or quickly findable, and it needs
fixing now. One file per hotfix:

```
docs/hotfixes/<YYYYMMDD>-<slug>.md
```

Use `/hotfix <description>` to start one.

**Do not break a hotfix into tasks.** Urgency is the entire reason this shape
exists; fix it, then fill the document in. The discipline here is not process,
it is the Prevention section.

## Template

```markdown
# Hotfix: <title>

- **Severity**: critical | high | medium
- **Date**: <YYYY-MM-DD>

## Incident

What happened, when, and what it cost. For this project, "critical" means a red
line was crossed — text was eaten, a secret escaped, the wrong thing committed
to an application.

## Root cause

Why it happened. Not "a bug in the processor" — the actual mechanism, with
`file:line`.

## Fix

What changed, and why that is the right fix rather than the nearest one.

## Verification

How it was proven fixed. A test that fails before and passes after beats any
amount of manual clicking. If it could only be verified by hand, say which of
the 16 smoke checks covered it.

## Prevention

**Which of the three layers should have caught this, and why did it not?**

- `.claude/hooks/` or `.githooks/` — the rule exists but no check encodes it
  → add the check plus its assertions to the suite
- the review gate — the rubric has no dimension for it
  → add one to `.claude/skills/task-review/SKILL.md`
- no layer could have — then this is a design defect
  → fix `docs/design/` and say which `§`

"Be more careful next time" is not an answer. If none of the three can be made
to catch it, write that down explicitly and say why.
```

Severity is mandatory. So is Prevention — a hotfix that does not feed back into
the harness or the design leaves the same trap in place for next time.
