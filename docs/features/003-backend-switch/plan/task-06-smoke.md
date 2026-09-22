# Task 6: Real-machine smoke (manual)

**Files:**
- Create: `docs/smoke-report-003.md`
- Modify: `docs/design/architecture.md` §5.6 (the derivation paragraph, from
  the results)

**Interfaces:**
- Consumes: Tasks 1–5, installed.
- Produces: the evidence that design §5.6 holds on the machine.

**Who observes.**
- **The notice is a transient panel.** The user watches every notice row (👁),
  pressing `Ctrl+Shift+B` on the physical keyboard.
- **The agent drives the rest** as in 002 Task 6: keys posted to TextEdit, a
  window screenshot only after checking it is frontmost, and the document's
  text read back over AppleScript.
- If a posted `Ctrl+Shift+B` does not reach Squirrel, as a posted
  `Ctrl+Shift+2` did not in Terminal (001 Task 11), the user presses it.

**Private content stays private.** TextEdit, in a new document. A browser, on
the local blank test page. No chat app is opened.

- [ ] **Step 1: Install and configure**

```bash
./scripts/install.sh
```

The user's `~/Library/Rime/ime_translate.yaml` is changed **only with the
user's yes**:
- the GLM lines become `cloud_` keys
- the local slot goes back to `translate`
- a backup is kept next to it

Then redeploy.

- [ ] **Step 2: The gate rows**

| # | Who | Steps | Passes when |
|---|---|---|---|
| G1 | 👁 | TextEdit, nothing typed: `Ctrl+Shift+B`, then again | The notice shows `云端翻译`, then `本地翻译`, each in full |
| G2 | agent | Local: `jintianyoudianlei`␣ ⏎; then cloud, the same | Local shows `  -> …`; cloud shows `  ☁ …`; the second ⏎ commits the English each time |
| G3 | agent | Local ⏎ showing, then `Ctrl+Shift+B`, ⏎, ⏎ | The prompt goes and the draft stays; the ⏎ shows `☁` and the same draft's cloud translation; the last ⏎ commits it |
| G4 | agent | `Ctrl+Shift+B` with no draft, three times | Nothing is inserted into the document |
| G5 | agent | Switch to cloud in TextEdit; translate in the browser's `<textarea>` | The browser's translation shows `☁` |
| G6 | agent | Cloud active; `Squirrel --reload`; translate | `☁`: the choice was remembered |
| G7 | 👁 + agent | `cloud_backend` commented out, redeploy; `Ctrl+Shift+B`; translate. Restore, redeploy | `云端未配置`; the translation shows `  -> …` |
| G8 | 👁 | Open the switcher menu (`Control+grave` or F4) | No notice switch is listed |
| G9 | agent | Shift+Enter; Esc on a prompt; `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎ | 001/002 unchanged: Chinese committed; draft kept; `readme` kept |

- [ ] **Step 3: The record rows**

| # | Who | Steps | Record |
|---|---|---|---|
| R1 | 👁 | A draft with every segment selected, then `Ctrl+Shift+B` | Whether the notice shows (F29 derivation: it does) |
| R2 | 👁 | `jintian` with its candidates open, then `Ctrl+Shift+B` | Whether the notice shows (F29 derivation: it does not) and whether the pinyin and its highlight are kept |
| R3 | agent | `cloud_base_url: https://127.0.0.2:9`, redeploy, cloud, translate; restore | The prompt: a cloud error, marked `☁ ✗` |
| R4 | agent | The log with `debug_log: true` for one switch and one translation; then off, and the log deleted | The slot name on each line, and no key |

- [ ] **Step 4: Write it down**

`docs/smoke-report-003.md` gets one line per row, saying how it was observed
(👁 user or agent). Design §5.6's derivation paragraph takes the R1/R2 results.

- [ ] **Step 5: Commit**

```bash
git add docs/smoke-report-003.md docs/design/architecture.md
git commit -m "docs: feature 003 smoke report"
```
