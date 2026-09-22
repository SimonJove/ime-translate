---
description: Review the design and a plan against upstream source, before work is built on them
---

Load the `design-review` skill and review $ARGUMENTS (or, with no argument, the
whole design set plus the open feature's plan).

1. Read `docs/design/` and the plan files that carry the mechanism — in full.
2. List every claim about upstream behaviour and read the source for each.
3. Walk the core loops and the host boundary with the real semantics, per state.
4. Label every finding: source reading, derivation or unverified. Never
   "measured" — that needs a person at the machine.
5. Write the findings where the skill's table says. A design *choice* that
   should change becomes a row in the open table of `docs/design/decisions.md`,
   with its **Blocks** cell filled in — it is not yours to change.
6. `./scripts/progress.sh decisions` to confirm what is now open, then report:
   verdict first, findings ranked by what they can overturn, what you changed,
   what you left for the user.
