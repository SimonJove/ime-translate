# Smoke report — feature 004, the Right Option tap

Run on 2026-09-22 against commit `3fdedd3`, with Task 2's text applied, as
installed by `install.sh`: Squirrel 1.1.2, librime 1.16.0. Plan:
[task-02-docs-smoke.md](features/004-option-tap/plan/task-02-docs-smoke.md).

**Who observed.** The user, with a physical keyboard, reported every row
correct ("Done, all correct").
- The agent's posted Right Option taps did not reach Squirrel. At the time
  the input source was ABC, and posted flag changes were already known to be
  unreliable (001 Task 10). No agent row is recorded as observed.
- The agent read `ime_translate.active` afterwards.

| # | Steps | Result |
|---|---|---|
| 1 | Nothing typed, one Right Option tap, in TextEdit | pass (user): the notice showed, and the backend switched |
| 2 | The same in a Chrome input box | pass (user) |
| 3 | The same in a terminal | pass (user) |
| 4 | The same in a WeChat input box, nothing sent | pass (user) |
| 5 | `Ctrl+Shift+B` | pass (user): no switch, no notice |
| 6 | `jintianyoudianlei`␣ ⏎, then a Right Option tap, then ⏎ | pass (user): the translation went and the draft stayed; the next ⏎ translated with the other backend |

**What this settles.** 004 was built because the user saw `Ctrl+Shift+B`
switch only with a draft open. With nothing typed, the Right Option tap
switched in Chrome, a terminal and WeChat, the kinds of app suspected of
taking the Control combination (design §5.6's note). Which app had taken
`Ctrl+Shift+B` was never recorded.

**Not observed:** Right Option held through a mouse click. It is a documented
edge (design §5.6), and by the user's choice it is not handled.
