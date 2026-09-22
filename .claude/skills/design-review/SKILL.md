---
name: design-review
description: Review the design and a feature's plan against what upstream actually does, before work is built on them. Use before a feature's first task starts, when the design changes, or when asked whether a plan is feasible / has problems.
---

# Design review

**Why this exists.** Every other layer here — edit hooks, git hooks, the task
review — guards the *implementation* against the design. Nothing guarded the
design against reality. On 2026-09-20 a read-through found that the core
Enter → preview → Enter loop did not close as designed, that Squirrel dumps the
draft as raw pinyin on focus loss, and that the life-or-death gate sat on the
two *safest* assumptions in the set. None of it was reachable from a unit test,
and the first task that would have met it was Task 10.

A design is a stack of claims about somebody else's code. This review reads
that code.

## When

- Before the first task of a feature starts (`progress.sh status` shows 0 done).
- When a design section is about to change.
- When the user asks whether the plan is feasible or has problems.

It is not the task review. That one reads a diff; this one reads `docs/design/`
and a feature's `plan/`, and produces no code.

## Procedure

1. **Read the design set and the plan** — all of `docs/design/`, the feature's
   `plan/README.md`, and the task files that carry the mechanism (for 001:
   tasks 1, 6–10). Skimming the index is not reading.
2. **List the upstream claims.** Every sentence of the form "librime does X",
   "`fluid_editor` never Y", "the context is rebuilt when Z". Each is a claim
   about code this project does not own.
3. **Read the source for each claim.** `rime/librime`, `hchunhui/librime-lua`,
   `rime/squirrel`, `rime/rime-prelude`, the schema repos. Name the file and the
   symbol. Where behaviour changed between versions, check tags — a claim can be
   true on master and false on what Homebrew installs.
4. **Walk the core loops with the real semantics.** Take the design's main
   flows and step through them using what the source says, not what the design
   says. Do it per *state*: the bugs live where the design assumed one state
   (an open segment) and the user is usually in another (everything confirmed).
5. **Walk the host boundary.** What does the frontend do that Lua never sees —
   focus loss, mouse selection, input-source switching, a blocked event loop?
   Invariants written for the Lua layer do not hold past it.
6. **Check the gate.** Are the life-or-death checks the riskiest assumptions, or
   merely the first ones written down? A gate on a safe assumption is false
   confidence. Anything that can overturn the design belongs in the spike, not
   in the first real-machine task.
7. **Check that what is tested is reachable.** Does the eval or the test feed
   the system through the same path the user will? Input that arrives through
   curl says nothing about whether it can be typed.

## Evidence labels

Every finding carries exactly one. Mixing them is how "per the plan it should be
X" ends up recorded as a result.

| Label | Means | Example |
|---|---|---|
| **source reading** | the code says so; file and symbol named | "`AutoCommitPunct` calls `Context::Commit()` unconditionally" |
| **derivation** | follows from source readings, by reasoning | "so the second Enter re-translates" |
| **unverified** | plausible, neither read nor measured; say in which direction it is unknown | "the text-input system may time out a blocked handler" |
| **measured** | a person saw it on the machine; versions recorded | only ever from a spike or a smoke check |

An agent produces the first three. **Only a human at the machine produces the
fourth** (`CLAUDE.md`). A review ends by saying which measurement would settle
each derivation.

## Where the output goes

| What | Where |
|---|---|
| Source readings, and derivations longer than a paragraph | `docs/design/upstream.md` §15 — a new F-row, or a new §15.x |
| Risks | `docs/design/risks.md` §12 — a short row in the register, the detail in §12.1 |
| New measurements needed | `docs/design/testing.md` §10.2 as a new S-item, plus a step in the spike task's plan file |
| A factual error in the design | fix the section; keep a note of what it used to say and why that was wrong |
| A design choice that should change | **do not change it.** Put an open-finding note on the section, and a row in the open table of `docs/design/decisions.md` — with a **Blocks** cell naming the tasks that build on it |
| Errors in a plan file | fix them only while that task has not started, and log it in `decisions.md`. After it has started the plan is immutable and the deviation goes in the task report |
| What was decided and applied | a dated entry in `docs/design/decisions.md` |

## What an agent does not decide

- A design choice. Record the finding, open a decision, stop (design §3.5: no
  quiet amendments to keep going).
- Anything in the *definition* half of a `progress.json` — the gate, a task's
  acceptance list. Propose it as an open decision.
- Closing an open decision. The user deletes the row, or tells you to.

## Reporting

Lead with the verdict — does the skeleton hold — then the findings ranked by
what they can overturn. For each: the claim, the label, the consequence, the
measurement that settles it. Separate what the docs already recorded from what
is new, and say plainly what you changed and what you left for the user.
