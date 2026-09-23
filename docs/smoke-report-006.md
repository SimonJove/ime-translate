# Smoke report — feature 006, a hint when Enter locks letters

Run on 2026-09-23 against `504e142`, as installed by `install.sh`: Squirrel
1.1.2, librime 1.16.0, in TextEdit, in the translation schema. Plan:
[task-02-docs-smoke.md](features/006-lock-hint/plan/task-02-docs-smoke.md).

**Who observed.** The agent first, with the document read back and the
TextEdit window captured; then the user, who reported the rows passing
(both features, all rows).

| # | Steps | Result |
|---|---|---|
| 1 | `jintian`␣ `readme`⏎ | pass (agent, user): the preedit reads `今天readme  [en]` |
| 2 | then `haode` | pass (agent, user): the hint is gone; `hao de` composes with the candidates `好的` |
| 3 | then ␣ ⏎ | pass (agent, user): `今天readme好的  -> Today's readme is good`, with no hint |

**Settled on the way.** The first hint, `  ✓英文`, was seen on the machine and
read like Chinese typed into the draft; the user chose `[en]` (decisions.md,
"Feature 006 designed").
