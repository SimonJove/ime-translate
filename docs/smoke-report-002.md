# Feature 002 real-machine smoke report

Feature 002, Task 6. The plan's table is in
[`task-06-smoke.md`](features/002-mixed-input/plan/task-06-smoke.md).

**Status: closed (2026-09-22).**
- **The agent's rows** are done, row by row. The agent drove them itself.
- **The rest** is confirmed by the user, as a whole: "At present, it is
  confirmed that there is no problem. You can close task 6." These rows need
  a physical Shift tap, Caps Lock, a person watching, or WeChat.
- **No row-by-row results** were given for them. They are labelled
  **user, overall** below.
- **Measurement.** Nothing in this feature was measured row by row by a
  person.

**How it was observed.** As in 001's report:
- **Keys.** The agent drove plain keys through System Events. Shift+letter and
  Shift+Space went through as CoreGraphics events: Shift down, the key, Shift
  up.
- **Screenshots.** TextEdit's window was captured only after checking it was
  frontmost.
- **Readback.** The document's text was read back over AppleScript.
- **Input source.** Squirrel was selected for the run and set back to ABC
  afterwards.

Every row says how it was observed:
- **agent** — readback and screenshot
- **user** — the user at the machine; only this is *measured*

## Environment

| Component | Version |
|---|---|
| macOS | 26, arm64 |
| Squirrel / librime / librime-lua | 1.1.2 / 1.16.0 / as bundled |
| Build | `f5a83a8` installed by `install.sh`; Squirrel restarted |
| `translate` | `/opt/homebrew/bin/translate --serve --port 8989`, under the LaunchAgent |

## Results

| # | Kind | Result | How |
|---|---|---|---|
| 18 | gate + record | **pass** — the preedit is `Hello`, raw. The first Enter locks it and the second commits `Hello` at once | agent |
| 19 | gate | **pass** — 001 rows 4–5: `I’m a little tired today.` committed | agent |
| 20 | gate | **pass** — the prompt showing, Esc: the prompt goes and `今天有点累` stays | agent |
| 30 | record | `readme`, Enter, Enter: the first Enter locks, the second commits `readme` (as row 36) | agent |
| 33 | gate | **pass** — after `readme`⏎ the preedit is `今天readme`, with no candidate window; then `今天readme好的`; nothing committed | agent |
| 34 | gate 👁 | **pass (agent)** — the preedit `今天readme好的  -> Today's readme is good`, then `Today’s readme is good` committed; the user confirmed it overall | agent; user, overall |
| 35 | gate | **pass** — `请pull request` in the preedit; `Please pull request` committed | agent |
| 36 | gate | **pass** — `readme` locked, then committed as is with no freeze | agent |
| 37 | record | `jintianreadme`⏎ with nothing selected: the whole draft becomes `jintianreadme`, as the design accepts | agent |
| 38 | gate | **pass** — the preedit reads `今天 好的` | agent |
| 39 | gate | **pass** — the first Enter only moved the caret: the whole input composed as `jin tian tian qi hen hao` with candidates. The second locked `jintiantianqihenhao` | agent |
| 40 | gate | **pass** — the prompt showing, Space: the prompt went and a space joined the draft. Enter then translated anew (`今天好的  -> Today is good.`); nothing committed | agent |
| 41 | record | The first BackSpace changed nothing. The second showed `今天re a d m` with candidates such as `热爱代码`. Enter locked `今天readm` | agent |
| 42 | gate 👁 | **pass (agent)** — `今天README`, locked; the user confirmed it overall | agent; user, overall |
| 47 | gate 👁 | **pass (agent)** — Shift+Space after `今天readme`: a space joined the draft, nothing committed; the user confirmed it overall | agent; user, overall |

**The other gate rows** — user, overall: pass, by the user's statement
above, with no row-by-row results.
- The Shift tap: rows 1–6, 8–13, 17, 32 and 46
- Caps Lock: rows 25 and 43
- The WeChat rows 22 and 45
- The 👁 confirmations of rows 34, 42 and 47

**The record rows** 7, 14–16, 21, 23, 24, 26–29, 31 and 44 were not reported
one by one. The plan made them optional records, and they stay unrecorded,
not assumed.

## Findings

- **No Rime error.** No ERROR log appeared after the install stamp, through
  both the install runs and this run.
- **An aside from the Task 5 review**, not checked here. `--reload` may load
  new Lua without the restart that `install.sh`'s notice asks for. That is a
  log reading and a source reading. It puts no text at risk, and it is a
  candidate for an `/issue`.
