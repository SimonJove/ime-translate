# Smoke report — feature 005, a more reliable Enter

Run on 2026-09-23 against `0bde6e9` and later, as installed by `install.sh`:
Squirrel 1.1.2, librime 1.16.0, in TextEdit, in the translation schema. Plan:
[task-05-docs-smoke.md](features/005-reliable-enter/plan/task-05-docs-smoke.md).

**Who observed.** The user ran rows 1-4 and reported them all passing
(both features, all rows). The agent ran row 5 and the plain path first, with
keys sent through System Events and the document read back; the user's report
covers them too.

| # | Steps | Result |
|---|---|---|
| 1 | Local: a sentence with a URL, the URL typed in English mode | pass (user): the English keeps the URL, spaced |
| 2 | Cloud active, Wi-Fi off: Enter | pass (user): `☁✗ -> …` within 2.5 s; Enter commits it |
| 3 | Row 2's state, Wi-Fi still off: Esc, Enter; then Wi-Fi on, Esc, Enter | pass (user): the cloud is asked again and the same fallback shows; with the network back, `☁ …` |
| 4 | Local service stopped: Enter, Enter, Shift+Enter | pass (user): `✗ 翻译服务未启动`; the second Enter commits nothing; Shift+Enter commits the Chinese |
| 5 | Local: translate, Esc, Enter, Enter | pass (agent; user overall): the translation shows again and commits. Whether that Enter made no request cannot be seen on the machine (`translate` answers in about 20 ms and logs no requests); the unit tests pin it |

**Found on the way, not a defect of 005:** the agent's synthetic keys can
misbehave (`keystroke "/"` never reached Rime; System Events modifiers add a
stray `a`). See [the issue](issues/20260923-slash-drops-draft.md).
