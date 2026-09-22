# Issues

Something is wrong and the cause is not yet known. One file per issue:

```
docs/issues/<YYYYMMDD>-<slug>.md
```

Use `/issue <description>` to start one. Single file, not a directory — an
investigation here will not grow a second document.

**An issue is not a feature.** A feature adds a capability and needs a plan; an
issue answers a question and may well end in `wontfix`. If the investigation
concludes that a real capability is missing, close the issue with that finding
and open a [feature](../features/README.md).

## Template

```markdown
# Issue: <title>

- **Status**: investigating | identified | resolved | wontfix
- **Opened**: <YYYY-MM-DD>
- **Affects**: <application / backend / task, if known>

## Symptom

What was observed. Exact input, exact output, which application, whether it
reproduces. "Sometimes it eats a sentence" is a starting point, not a symptom —
write down what you actually saw.

## Investigation

Steps taken and what each ruled in or out. Cite `file:line` and log excerpts.
Record the dead ends too: the next person needs to know what has been tried.

## Resolution

What fixed it, or why `wontfix`. If code changed, name the commit. If a design
section was wrong, say which `§` and whether it has been corrected.
```

`Status` starts at `investigating` and is updated by whoever advances the work.
`wontfix` is a legitimate ending — recording why is the point.
