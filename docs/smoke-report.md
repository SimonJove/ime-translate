# Task 10 real-machine smoke report

Feature 001, Task 10, Step 6. The plan's table is in
[`task-10-wiring.md`](features/001-zh-en-ime/plan/task-10-wiring.md).

**How it was observed** (decisions.md, "Task 10 revised before start"):
- The agent drove the machine:
  - plain keys through System Events
  - keys with modifiers, clicks and scrolls as CoreGraphics events
  - TextEdit's window captured with `screencapture -x`, only after checking it
    was frontmost
  - the document's text read back over AppleScript. TextEdit includes marked
    text, so a readback shows the preedit and the prompt.
- `debug_log` was on from the start until 17:08:30, and every row run in that
  time was checked against its log lines. Later runs were checked by readback
  and screenshots only:
  - row 21 by swipe
  - the full-width row
  - the Shift+Enter re-runs
  - the mixed-input trials
- The plan had the user watch the rows marked 👁. None was watched live. By the
  user's decision after review, round 1, agent observation is accepted for them
  (decisions.md, "Task 10 review, round 1"), and they are labelled so below.
  Row 21 was run later, after round 2, at the user's instruction.
- Screenshots were kept outside the repository.

Every row below says how it was observed:
- **agent** — the agent's readback, log and screenshot; "accepted" marks a 👁
  row the user accepted on that basis
- **agent, at the user's instruction** — run by the agent because the user
  asked it to
- **user** — the user at the machine; only this is *measured*

## Environment

| Component | Version |
|---|---|
| macOS | 26, arm64 |
| Squirrel / librime | 1.1.2 / 1.16.0 (as in the spike report) |
| `translate` | `/opt/homebrew/bin/translate --serve --port 8989`, under the LaunchAgent `local.ime-translate.translate-serve` |
| Schema | `luna_pinyin_translate`, paired with `luna_pinyin_simp` |

## Install

**Two runs of `scripts/install.sh`.**
- The first installed eight Lua files, the `rime.lua` binding, the schema,
  `default.custom.yaml`, the config and the plist, and started the service.
- The second printed no `installed`, `started`, `bound` or `wrote` line. That
  covers the idempotency acceptance item. Earlier, a sandbox run with
  `launchctl` and Squirrel stubbed also checked the handling of a foreign
  `default.custom.yaml`, and of a `rime.lua` without a trailing newline.

**The built schema** (`build/luna_pinyin_translate.schema.yaml`):
- `lua_processor@ime_translate_processor` comes first among the processors
  (as installed at the end; see "Shift+Enter switched to English" for the
  order tried in between).
- There are 32 `key_binder` bindings. The preset's `Control+Shift+T` → this
  schema comes first, and this schema's `Control+Shift+T` → `luna_pinyin_simp`
  comes last.
- `zh_simp` has `reset: 1`. `simplifier/option_name` is `zh_simp`.
- `half_shape` `,` is the plain string `，`.

**The built `default.yaml`.** `schema_list` holds the eight stock schemas and
then `luna_pinyin_translate`, so `schema_list/+` works (observed by the agent). Deploy
logged no errors. The only warnings were the optional `grammar.yaml` (stock
`luna_pinyin` logs the same) and the build file not existing before the first
build.

**R8 answered.** `Translation.framework` works from the LaunchAgent: `curl` to
`:8989/translate` returned `{"translatedText":"Receive"}` for `收到`, with the
service running under launchd (agent).

## Results

The kinds are `gate` (must pass) and `record` (passes once written down).

| # | Kind | Result | Observed |
|---|---|---|---|
| 1 | gate | **pass** — the preedit is underlined and nothing is committed | agent |
| 2 | gate | **pass** — the draft grows to `今天有点累补过`, uncommitted | agent |
| 3 | gate | **pass** — the comma joins the draft (`今天有点累补过，`) | agent |
| 4 | gate 👁 | **pass (agent)** — the preedit reads `今天有点累补过，  -> I'm a little tired today.`, nothing committed. The debug log also recorded the user's own typing in a terminal during the run being translated and committed; that is the agent reading the log, not the user watching a row (not quoted here) | agent, accepted |
| 5 | gate 👁 | **pass (agent)** — the English commits at once with no Chinese residue. (TextEdit's smart quotes turn `'` into `’`: TextEdit's own substitution) | agent, accepted |
| 6 | gate | **pass** — `好的` → `Okay`, translated and committed | agent |
| 7 | gate | **pass** — the prompt goes; `a` joins the draft (`今天有点累a`) | agent |
| 8 | gate | **pass** — state B shows `今天bu guo  -> Today is just` with Rime's window open. `2` selects `补过` and the prompt goes | agent |
| 9 | gate | **pass** — the prompt goes, and BackSpace reopens the last confirmed selection (`jin tian you dian lei`), exactly as it does with no translation (a control run gave the same), so this is native | agent |
| 10 | gate | **pass** — the prompt goes, `今天有点累` stays, and `ma` continues it | agent |
| 11 | gate | **pass** for the commit — `今天有点累` commits; the log has `commit draft` and no `translate` line. The Shift toggle this key could trip is covered in "Shift+Enter switched to English" | agent |
| 12 | gate | **pass** — the preedit ends with `  ✗ 翻译服务未启动`, and Enter commits `今天有点累` (log: `ERR conn_refused`, then `commit draft`). Method changed: see deviations | agent |
| 13 | gate | **pass** — with a 1.2 s stub, `abcde` typed during the freeze all landed in the draft in order (`今天有点累a b c de`); the prompt is gone and nothing reached the app early | agent |
| 14 | record | The prompt shows `Line one` and `Line two` on two lines inside the preedit. The commit inserts `Line one\nLine two` as is. The debug log line is broken across two lines (see findings) | agent |
| 15 | gate + record | **pass** — a second document showed and committed its own `Okay`, never the first one's translation. Record: the first document, left with its prompt showing, received the raw pinyin `jintianyoudianlei` (spike S12, D2). Retyping the same sentence there translated it; nothing stale was committed | agent |
| 16 | gate | **pass** — `luna_pinyin_simp` is native (9 candidates, `你好` committed on space). Back again: 5 candidates, Simplified. A new document starts in the translation schema, Simplified. The switcher lists `朙月拼音·译` with `汉`, then the stock schemas. Record: the half draft (`jin tian`) is dropped on switching, as §5.1 says | agent |
| 17 | gate | **pass (posted keycode)** — keypad Enter, sent as keycode 76, translated and then committed. No physical keypad here: the key itself is unverified | agent |
| 18 | gate | **pass** — after Left, the first Shift+Enter committed nothing and moved the caret to the end. The second committed `今天天气很好`, `好` included | agent |
| 19 | gate | **pass** — the first Enter only moved the caret, the second translated the whole draft (`The weather's good today`), the third committed it | agent |
| 20 | record | Left, then Down, then Enter: nothing committed; the input was recomposed whole and the highlight fell back, as source reading expected | agent |
| 21 | gate 👁 | **pass** — state B, prompt showing: a trackpad-like scroll gesture on Squirrel's window (continuous pixel events, phases began/changed/ended, posted) paged it: the highlight moved from `不过` to `不谷` while the old prompt stayed on screen (§6.2's residual, seen). Esc then kept the draft `今天bu guo` and dropped the prompt. An earlier single line-unit wheel event did not page. Also passed with a click as the no-key edit (`今天不果` kept) | agent, at the user's instruction |
| 22 | gate 👁 | **failed, fixed, pass** — the click removed the prompt and the next Enter committed `Today is just` unseen (as derived in Task 9's review). Fixed (decisions.md, "Task 10 smoke: Enter commits only a translation on screen"). Re-run: Enter shows `今天不过  -> Today is just` again, the second Enter commits | agent, accepted |
| 23 | gate 👁 | **pass** — a click on `不果` removed the prompt, and Enter translated the new draft (`It's not good today.`) rather than committing the old English | agent, accepted |
| 24 | record | With the prompt showing, a Shift press (posted as a flagsChanged event, as a physical key sends it) voided the translation and the prompt went. The Shift+Esc that followed arrived in idle and **wiped the whole draft**: the native cancel, as source reading expected (Task 9 review, round 2). See findings | agent (emulated key) |
| 25 | record | Control+g with the prompt showing wiped the draft, as expected and accepted | agent |
| 26 | record | With a draft open, Caps Lock (a posted flagsChanged event) **cleared the whole draft**, committing nothing. The input source stayed on Squirrel. This is the inherited `Caps_Lock: clear`: R15's second path, still open. See findings | agent (emulated key) |
| 27 | gate 👁 | **pass** — in WeChat's File Transfer chat (title checked first): the first Enter showed `今天有点累  -> I'm a little tired today.` underlined in the input box; the second put `I'm a little tired today.` into the box as plain text, with Send enabled and **nothing sent**. The agent then emptied the box; no third Enter was pressed | agent, accepted; the user opened the chat |
| 28 | gate | **pass** — Enter, then Esc: `今天有点累` stays in WeChat's input box, underlined | agent |

## After review, round 1

- **Full-width punctuation** (review yellow 4, the user's decision). The schema's
  change 4 now covers `full_shape` as well as `half_shape`; the built schema
  holds plain strings in both. Re-run by the agent: the switcher showed `半`,
  `Control+Shift+3` turned it to `全`, and in full-width `jintianyoudianlei`,
  space, `,` gave the draft `今天有点累，` with nothing committed. Then
  `Control+Shift+3` restored `半`.
- **The installer** (review yellows 2-3). Two failures were re-run in a sandbox,
  with `HOME` redirected and `launchctl` and Squirrel stubbed:
  - A read-only installed file now prints `FAILED to install …` and exits 1.
  - A failing `launchctl bootstrap` prints `FAILED to start …`, still redeploys
    and prints the restart notice, and exits 1.
- **The config template** shows `security … -w` with `-w` last, so `security`
  prompts and the key stays out of shell history. It also says a restart needs
  a focus change.
- **Candidates per page** differ: 9 in `luna_pinyin_simp` (the user's
  `luna_pinyin.custom.yaml` sets `menu/page_size`), 5 in this schema. A
  `luna_pinyin_translate.custom.yaml` with the same patch would align them; not
  done, since it is the user's own setting.
- **An interrupted deploy.** At 16:58 the smoke driver restarted Squirrel
  while `install.sh`'s redeploy was still running. The Rime ERROR log shows it;
  the next start deployed again. Harmless, noted for completeness.

## Shift+Enter switched to English (found by the user in use)

After the run, the user reported that after Shift+Enter the IME was in English.

**Reproduced by the agent** with a physical-style sequence posted from one
process: Shift down (flagsChanged), Return down and up carrying Shift, Shift up.
`今天` committed, and the next `n` went into the document as a plain letter.

**Row 11 had passed** with a single Return event carrying the Shift flag and no
separate Shift events. That method could not show the defect. This is a limit
of row 11 as run, not a pass.

**Cause:** see decisions.md, "Shift+Enter switched the IME to English". In
short, `ascii_composer` never saw the Return, so the Shift release counted as a
lone tap.

**First fix, withdrawn.** The processor was moved to right after
`ascii_composer`. The re-run with the same sequence passed:
- After Shift+Enter, `n` stayed pinyin.
- Enter, Enter still translated and committed.
- A lone tap still toggled English.

Review, round 3 found that `ascii_composer` can then reject an Enter to the
application ahead of the processor, which is R15's lost draft (decisions.md).

**Final fix (the user's decision).** The processor goes back first, and
`ascii_composer`'s `Shift_L` and `Shift_R` are `noop` (schema change 8). The
built schema shows both.

**Re-run after the final fix, agent:**
- Enter, Enter translates and commits (`好的` → `Okay`).
- **The agent could not settle Shift.** Posted Shift events reached Rime only
  intermittently:
  - One run delivered the press, since the prompt went. Review, round 4 showed
    that it could not tell the fix from the defect.
  - A control in `luna_pinyin_simp`, where a tap should toggle, did not
    toggle, so the agent's taps could not be trusted.
- **Measured by the user, on the physical keyboard:**
  - After Shift+Enter, pinyin shows the candidate window: Chinese.
  - After a lone Shift tap, it is still Chinese.

  This is the gate evidence for the fix.

**Rows 11 and 18** used the same single-event Shift+Return. That method commits
correctly but cannot show a Shift toggle. Row 11's pass stands for the commit
only.

**Harness note.** Posted flagsChanged events reached Squirrel until about
19:28, then stopped. Posting every modifier as released brought them back once,
then they failed again. The cause is not found.

## Mixed Chinese and English in one draft (after the run, at the user's question)

Observed by the agent in TextEdit:

- **A capital first letter, then space, works.** The sequence was
  `qingnizhengliyige`, `Readme`, space, `wenjian`, space. It gave the draft
  `请你整理一个Readme文件`, and Enter translated it to
  `Please sort out a Readme file.`.
  - The capital keeps the word literal, as spike S14 saw.
  - The space ends the literal word, and pinyin converts again after it.
  - Without the space, the pinyin that follows stays literal too
    (`Readmewenjian`).
- **Left Shift** (`ascii_composer/switch_key/Shift_L: inline_ascii`). A single
  posted tap (press and release 60 ms apart, one process) switches the draft to
  English in place. An earlier two-process tap did not trigger it.
  - After the tap, `readme` stayed literal: `请你整理一个readme`.
  - **Tapping back to Chinese re-read it as pinyin.** `wenjian` then gave
    `请你整理一个热爱多么文件`.
  - A space typed in English mode goes into the draft (`readme `) and confirms
    nothing. After tapping back, the same re-reading happens.

  So inline English holds only as the draft's tail. Mixed English in the middle
  of a sentence needs a design change; the user has asked for one.
- **Right Shift** was `commit_text` in the inherited config.
  - What that did here is a derivation, and it was stated wrongly before. The
    Task 10 review read `commit_text` as `ConfirmCurrentSelection`, which under
    `fluid_editor` does not commit to the application.
  - It is moot now: both Shift keys are `noop` in this schema (change 8).
- **Left Shift** is also `noop` now, so the observations above describe the
  stock config, as run before change 8.

## Findings

- **Two keys still discard a whole draft**, both recorded rather than gated,
  both native Rime behaviour reached through the translation schema:
  - Caps Lock (row 26, the inherited `Caps_Lock: clear`).
  - Shift+Esc while a translation shows (row 24: the Shift press voids the
    phase, then the native cancel runs).

  Neither commits anything unseen. Each loses typed text, so each is a
  candidate for `/design-review` (R15's second path; Task 8's modified-Esc
  note).

- **Row 22 was a real defect**, fixed in the processor before this task
  closes; see above.
- **Squirrel relaunches only on a focus change.** After `Squirrel --quit`, a
  key or an input-source switch did not bring it back; switching to another app
  and back did. `install.sh`'s closing message said "on the next key" and was
  corrected.
- **The debug log writes a multi-line translation raw**, so one entry spans
  two lines. It is cosmetic; the log is off by default.
- **TextEdit stops answering AppleEvents while an autocorrect bubble is up.**
  This is a harness note: readbacks need a hard timeout, and an Esc with no
  composition open dismisses the bubble.
- **The debug log holds what the user types** while `debug_log` is on. It was
  on for this run only; the config is restored afterwards.

## Deviations from the plan

- **Schema change 8** (after review, round 3; the user's decision):
  `ascii_composer`'s `Shift_L` and `Shift_R` are `noop`. The processor stays
  first, as planned. An intermediate order, with the processor behind
  `ascii_composer`, was installed and withdrawn the same day.

- **Row 12:** the backend was not stopped with `launchctl bootout`, because
  that call was declined. The config pointed `base_url` at a closed port
  instead. It is the same curl exit 7, the same `conn_refused`, and the same
  message.
- **Row 15:** a second TextEdit document stood in for Notes, which holds the
  user's private content. It is still a second input client.
- **Row 17:** a posted keypad keycode, not a physical key.
- **The stub:** it ran from the agent's scratch directory, not `/tmp`.
- **`scripts/install.sh`:** the closing message was corrected, as above.
- **Outside Task 10's files:** `rime/lua/ime_translate_processor.lua` and
  `tests/test_processor.lua` carry the row-22 fix.
