# Task 6: Real-machine smoke (manual)

**Files:**
- Create: `docs/smoke-report-002.md`
- Modify: `docs/design/architecture.md` (§5.5's "Not measured" list)

**Interfaces:**
- Consumes: the installed build from Task 5, with Squirrel restarted.
- Rows 33–45 were added on 2026-09-22 with the redesign (decisions.md,
  "Feature 002 redesigned"), before this task started.
- Produces: the record of what a person saw. Each row's result says how it was
  observed: by the user, by agent readback, or by an agent screenshot.

**Who does what.**
- The Shift rows need a physical key. The agent's posted Shift events proved
  unreliable in 001 Task 10. So **the user presses Shift and watches**, and the
  agent supplies the sequence and records the answer.
- Rows with no Shift in them, the 001 regressions, may be driven by the agent
  as 001 Task 10 was, with a TextEdit readback.
- Never write "per the plan it should be X" as a result.

**Setup.**
- TextEdit, a new document. The translation schema is active (Ctrl+Shift+T),
  and the mode is Chinese.
- "Tap" means a lone Shift tap: press and release, nothing else in between,
  under half a second.
- Capitals: Shift+letter, or Caps Lock, which is `noop` in this schema
  (D7). Rows 25 and 43 check that Caps Lock loses nothing.
- **Section G is the main way** (the Enter way, design §5.5). Sections A–F
  cover the Shift tap, which is the supplement, and what earlier reviews found.
  The row numbers stay as they were, because the design documents cite them.
- **gate** rows must pass. **record** rows pass once written down. 👁 means the
  user watches.

| # | Action | Expected | Kind |
|---|---|---|---|
| | **A. Mixed drafts** | | |
| 1 | `qingnizhengliyige`, tap, `readme`, tap, `wenjian`, space | The preedit reads `请你整理一个readme文件`; nothing committed. The space selects `文件`: under the Enter way, Enter on unselected pinyin would lock it as letters | gate 👁 |
| 2 | Enter | The prompt shows an English sentence that keeps `readme`; nothing committed | gate 👁 |
| 3 | Enter | The English commits; no Chinese residue | gate 👁 |
| 4 | `jintian`, tap, `readme`, tap, `haode` — no space or selection before the first tap | `今天readme好的` | gate 👁 |
| 5 | `qing`, tap, `pull request`, tap, `haode` | `请pull request好的`, with the space kept | gate 👁 |
| 6 | `yong`, tap, `git`, tap, `tijiao`, tap, `README` (Shift+letters), tap, `wenjian`, space, Enter | The preedit reads `用git提交README文件`. The capitals did not switch the mode. The translation keeps `git` and `README` | gate 👁 |
| 7 | Inside a draft in English mode, type `v2.0 (beta)` | Record what enters the draft. Expected by source reading (F19): every printable ASCII character, space included | record 👁 |
| | **B. The tap itself** | | |
| 8 | No draft: tap, type `hello`, tap, type `nihao` | `hello` goes straight into the document with no preedit; then `nihao` is pinyin again | gate 👁 |
| 9 | `jintian`, hold Shift about a second, release, type `haode` | No switch: `haode` is pinyin | gate 👁 |
| 10 | Row 4 with Right Shift | Same as row 4 | gate 👁 |
| 11 | `jintian`, Shift+Enter, then type `haode` | `今天` commits; `haode` is pinyin: the mode did not switch (001's Shift+Enter bug stays fixed) | gate 👁 |
| 12 | `jintian`, Ctrl+Shift+T, Ctrl+Shift+T | The schema switches out and back; the mode does not flip | gate 👁 |
| 13 | `jintiantianqihenhao`, Left once, tap; then tap again, type `ok` | The first tap only moves the caret to the end, no switch. The second locks and switches; `ok` is English | gate 👁 |
| 14 | `jintian`, tap, tap, `haode` — two taps with nothing between | Record the draft. Expected by derivation (upstream §15.5): `今天好的`, the second confirm doing nothing | record 👁 |
| 15 | `jintian`, then Shift+click elsewhere in the document within half a second | Record it. Expected by derivation: a tap, since Squirrel receives no mouse events (F21). What happens to the draft is the click's, as without Shift | record 👁 |
| 16 | Record whether Squirrel shows its mode notice on a tap | Expected by source reading (F24): the switch's state label, `西文` or `中文` | record 👁 |
| | **C. The mode and drafts with no Chinese** | | |
| 17 | `ni`, tap, `hello`, Enter, Enter; then type `world` | The sentence translates and commits. `world` goes straight into the document: the mode stayed English | gate 👁 |
| 18 | Chinese mode, no draft: `Hello` (Shift+h, then `ello`), Enter, Enter | Record the preedit (expected by source reading of the stock recognizer: `Hello`, raw). The first Enter locks it (§5.5, the Enter way); the second commits `Hello` at once, with no freeze and no translation | gate 👁 + record |
| | **D. Feature 001, unchanged** (the agent may drive these) | | |
| 19 | 001 rows 4–5: `jintianyoudianlei`, space, Enter, Enter | As in 001 | gate |
| 20 | 001 row 10: the prompt showing, Esc | As in 001 | gate |
| 21 | 001 row 22's setup: State B, the prompt showing | Record that it cannot be reached. Under the Enter way, Enter on State B locks the open pinyin as letters, so no translation shows while a segment is open | record |
| | **E. WeChat, the File Transfer chat** | | |
| 22 | Row 4's sequence, space, Enter, Enter | The English, `readme` kept, is in the input box and **not sent**; only a separate Enter sends | gate 👁 |
| | **F. Found by the design review** (TextEdit) | | |
| 23 | (a) `jintian`, tap, `readme`, tap, BackSpace, BackSpace. (b) Again from the start: … tap, BackSpace, tap, BackSpace, BackSpace | Record each screen. Expected by derivation (R17): in (a) the first BackSpace changes nothing and the second leaves `readm` read as pinyin; in (b) `readm` stays letters | record 👁 |
| 24 | `jintian`, tap, BackSpace, BackSpace | Record it. Expected by derivation (R17): the first changes nothing, the second leaves `jintia` as letters | record 👁 |
| 25 | `jintian`, tap, `ok`; Caps Lock on, type `ok`; Caps Lock off | **No text is lost.** With `Caps_Lock: noop` (D7) the capitals `OK` go into the draft | gate 👁 |
| 26 | Tap to English in one TextEdit document, then open a second one and type; then the same in VS Code, if installed | Record each starting mode. Expected by derivation (F24): the new document starts in Chinese; VS Code starts in English (`app_options`) | record 👁 |
| 27 | `jintian`, `Control+Shift+2` | Record the draft. Expected by derivation: `jintian` is read again as letters, not locked | record 👁 |
| 28 | `jintiantianqi`, Down until a shorter candidate is highlighted, tap | Record it. Expected by derivation: only the highlighted part locks, and the rest becomes English letters | record 👁 |
| 29 | Within half a second: (a) left down, right down, right up, left up; (b) left down, right down, left up, right up | Record each. Expected by derivation (F21, Task 1 review): (a) switches, since it arrives as a lone left tap; (b) does not, since it arrives as a left press and a right release | record 👁 |
| 30 | TextEdit, Chinese mode, no draft: `readme`, Enter, Enter | The first Enter locks `readme`; the second commits it at once. That is the Enter-Enter rhythm of 001 again: the review's worry, a first Enter that commits, no longer applies | record 👁 |
| 31 | `jintian`, tap, `readme` | Record whether a candidate window shows while English is typed in English mode. Expected: none, since the raw translator was dropped (D8) | record 👁 |
| 32 | `jintian`, space (selects `今天`), tap, `readme` | `今天readme`: the tap after a selection still switches, although its confirm meets the empty segment and returns false (F20; 002 Task 4 review) | gate 👁 |
| | **G. The Enter way — the main way** (design §5.5; rows with no 👁 may be driven by the agent with a TextEdit readback) | | |
| 33 | `jintian`␣ `readme`⏎ `haode`␣ | The preedit reads `今天readme好的`, with no candidate window after the ⏎; nothing committed | gate |
| 34 | ⏎, then ⏎ | The prompt shows English that keeps `readme`; then it commits | gate 👁 |
| 35 | `qing`␣ `pull`⏎ ␣ `request`⏎ ⏎ ⏎ | `请pull request`; the English keeps `pull request` | gate |
| 36 | `readme`⏎ ⏎ | The first ⏎ locks, the second commits `readme` at once, with no freeze | gate |
| 37 | `jintianreadme`⏎, nothing selected | The whole draft becomes `jintianreadme`: the accepted cost of the Enter way | record |
| 38 | `jintian`␣ ␣ `haode`␣ | The draft reads `今天 好的`: the second space is literal | gate |
| 39 | `jintiantianqihenhao`, Left once, ⏎, ⏎ | The first ⏎ only moves the caret to the end; the second locks the whole input as letters | gate |
| 40 | A translation showing (row 34's first ⏎), then ␣ | The prompt goes, a space joins the draft, and the next ⏎ translates anew; nothing committed | gate |
| 41 | `jintian`␣ `readme`⏎, BackSpace, BackSpace, ⏎ | Record each. Expected (agent-observed in the spike): the first BackSpace changes nothing; the second shows `readm` as pinyin with candidates; ⏎ locks `readm` | record |
| 42 | `jintian`␣, `README` with Shift+letters, ⏎ | `今天README`, locked | gate 👁 |
| 43 | `jintian`␣, Caps Lock on, `readme`, ⏎, Caps Lock off | `今天README`, nothing lost (D7) | gate 👁 |
| 44 | Watch Squirrel's status notices during rows 33–38 | No `中文` / `西文` notice on ⏎ or ␣: the mode is never switched | record 👁 |
| 45 | WeChat, the File Transfer chat: `qing`␣ `pull`⏎ ␣ `request`⏎, then ⏎ once to translate and ⏎ once to commit — no more | The English is in the input box and **not sent**. Another Enter would reach WeChat on an empty draft, and that is a send: do not press it | gate 👁 |
| 46 | `jintian`, tap, `readme`, Enter, Enter | English mode: the first Enter translates `今天readme` at once, and the second commits it | gate 👁 |
| 47 | `jintian`␣ `readme`⏎, then Shift+Space | A space joins the draft; nothing is committed | gate 👁 |

If a gate row fails, go back to the task that owns the behaviour and fix it
there. Do not patch around it here.

- [ ] **Step 1: Run the rows**

In WeChat, check that the chat title is File Transfer before typing, and
never press send.

- [ ] **Step 2: Write the report**

`docs/smoke-report-002.md` follows `docs/smoke-report.md`:
- the setup: the build commit, the Squirrel and librime versions, and who
  observed what
- one result row per table row, each with how it was observed
- the findings and deviations

- [ ] **Step 3: Update the design**

In §5.5, move whatever was measured out of "Not measured" and name the row.
Anything still unmeasured stays listed.

- [ ] **Step 4: Commit**

```bash
git add docs/smoke-report-002.md docs/design/architecture.md
git commit -m "docs: real-machine smoke for mixed input"
```
