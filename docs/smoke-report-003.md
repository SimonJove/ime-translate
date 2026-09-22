# Smoke report — feature 003, the backend switch

Run on 2026-09-22 against commit `1ead9d5`, as installed by `install.sh`:
Squirrel 1.1.2, librime 1.16.0. Plan:
[task-06-smoke.md](features/003-backend-switch/plan/task-06-smoke.md).

**How each row was observed.**
- **👁 user**: the user pressed the keys and watched.
- **agent**: the agent drove TextEdit, and Chrome for G5. Keys were posted,
  windows captured only while frontmost, and the document read back over
  AppleScript.
- **Evidence the agent read:** the IME's debug log, on for the run and deleted
  afterwards, and `~/Library/Rime/ime_translate.active`.
- A posted `Ctrl+Shift+B` reached Squirrel once TextEdit's input source was
  Squirrel.

**Setup.**
- The user's config was migrated, with the user's yes. The GLM lines became
  `cloud_` keys, the local slot went back to `translate`, and the cloud
  timeout was set to 2500.
- The backup is `ime_translate.yaml.bak-before-003`.
- The cloud model was the user's `glm-5-flash` until G2's retry. For the
  retry the user chose `glm-4-flash-250414`.

## Gate rows

| # | Who | Result | Observed |
|---|---|---|---|
| G1 | 👁 | pass | The user pressed `Ctrl+Shift+B` three times with nothing typed. The notices were `云端翻译`, `本地翻译` and `云端翻译`, each in full (user). The log shows the same three switches, the active file said `cloud`, and nothing was inserted |
| G2 | agent | pass | **Local:** `今天有点累  -> I'm a little tired today.`, and the second ⏎ committed the English. **Cloud:** with `glm-5-flash` every answer failed, marked `☁ ✗ 翻译失败` or `☁ ✗ 翻译超时`, and the second ⏎ committed the Chinese (see "The cloud backend" below). With `glm-4-flash-250414`, chosen by the user, the first try showed `今天有点累  ☁ Feeling a bit tired today 😩`, with ☁ drawn as a cloud glyph in the preedit. The second ⏎ committed `Feeling a bit tired today 😩`. The model added the emoji; that is the model's style, not the IME |
| G3 | agent | pass | A local translation was on screen. `Ctrl+Shift+B` removed the prompt and kept `今天有点累`, and the log shows `switch backend: cloud`. The next ⏎ translated the same draft on the cloud slot (`translate [cloud]`), shown with `☁` |
| G4 | agent, 👁 | pass | Three physical presses and several posted ones, all with nothing typed. Nothing was inserted into the document |
| G5 | agent | pass | Switched to cloud in TextEdit, then translated in a new Chrome window on the local test page. The log shows `translate [cloud]` for Chrome's session |
| G6 | agent | pass | Cloud was active, then `Squirrel --reload`. The file still said `cloud`, and the next translation ran on the cloud slot |
| G7 | 👁 + agent | pass | With `cloud_backend` commented out and a redeploy, `Ctrl+Shift+B` showed `云端未配置` (user) |
| G8 | agent | pass | F4 opened the switcher menu. Folded, it showed `中 / 半 / 汉 / 。`. Unfolded, it listed four switches, `中文`, `半角`, `汉字` and `。`, then the schemas on page 2. No notice switch was listed. The user first answered `有的`; the agent's two captures show that the notice switches are not there |
| G9 | agent | pass | Shift+Enter committed `今天`. Esc on a prompt kept `今天有点累`. `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎ gave `今天readme好的  -> Today's readme is good`, then committed `Today's readme is good` |

## Record rows

| # | Who | Record |
|---|---|---|
| R1 | 👁 | A draft with every segment selected, then `Ctrl+Shift+B`: the notice **shows** (`云端未配置`, in full). As derived from F29 |
| R2 | 👁 | `jintian` with its candidates open, then `Ctrl+Shift+B`: **no notice**, the pinyin stays, and a highlight moved by hand **returns to the first candidate**. As derived from F29 and F20 |
| R3 | agent | Cloud errors were marked `☁ ✗ 翻译失败` (`http_error`) and `☁ ✗ 翻译超时` (`timeout`) |
| R4 | agent | 36 log lines were written during the run. Every translate or switch line names its slot (`translate [local]`, `switch backend: cloud`, …). No line holds a key or a header. The log was deleted afterwards |

## Found along the way

- **A 5000 ms cloud timeout lost the draft in TextEdit.** Observed by the
  agent. With `glm-4-flash` and `cloud_timeout_ms: 5000` set temporarily, the
  IME blocked for 5 s and timed out. Afterwards TextEdit showed no draft: the
  preedit, prompt included, was gone. That is spike S13's finding, now seen at
  5000. The user's own config had carried `timeout_ms: 5000` before the
  migration.
- **The cloud backend.** Measured by the agent through the IME, which holds
  the key; the agent cannot read the Keychain.
  - `glm-5-flash` is not a model Zhipu offers. Every request failed at once
    with `http_error`.
  - `glm-4-flash-250414` and `glm-4-flash` both timed out at 2.5 s.
  - `glm-4.7-flash` answered `rate_limited` in about 1.3 s.
  - An unauthenticated request to the same endpoint took 0.7–2.1 s end to
    end, of which the TLS handshake alone was 0.4–1.8 s. The TCP connect took
    about 3 ms, which suggests a local proxy in the path.
- **Residue in an older TextEdit document.** A document left from earlier
  testing held the plain text `今天有点累  -> A bit tired today.`, the
  prompt included. The likely cause is a draft whose translation was on screen
  when the input source or focus changed. That would be a variant of D2, which
  recorded raw pinyin. **Not reproduced, and not caused by 003**; it is for an
  issue.
