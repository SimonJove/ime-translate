# Phase 0 spike report

**Status: every check has run.** The three life-or-death items — S1, S3 and S11 —
hold, and the user recorded the gate as **pass** on 2026-09-20. Two acceptance items are only partly met: Slack is not installed (S7, S13),
and S8's apfel half cannot run on this machine. Probes removed and the IME
restored on 2026-09-20 (Step 10).

**How the evidence was taken.** S1–S4 and S9/S10 were observed by the user at
the machine. From S11 on, the agent drove the machine itself: keystrokes posted
through System Events or CoreGraphics (they travel the real input-method path —
the probe logged every one), screens captured with `screencapture -x`, which
does not take focus, and application text read back over AppleScript. Every
verdict is a measurement unless a line says *derivation* or *source reading*.

## Environment

All later re-verification is measured against these versions.

| Component | Version | How it was read |
|---|---|---|
| macOS | 26, arm64 | `sw_vers` |
| Squirrel | 1.1.2 (`CFBundleVersion`) | `Info.plist` |
| librime | **1.16.0** | `otool -L` current version, the embedded `rime_version` string, and `installation.yaml` all agree |
| librime-lua | no version string; dylib built 2026-01-13, bundled with Squirrel 1.1.2 | `strings` on `rime-plugins/librime-lua.dylib` |
| Lua inside librime-lua | **5.4.6** | `@$LuaVersion` string in the plugin dylib |
| Lua for headless tests | 5.4.8 (asdf) | `lua -v` |
| Schemas | stock `luna_pinyin` from SharedSupport; spike schema `spike_fluid` derived from it | — |

**librime 1.16.0 places this machine on design §15.2 F6's "1.11.2 and later"
branch**: the trailing empty segment of a fully confirmed composition *is*
translated. §15.3's State A derivation therefore applies here, and S11 is the
measurement that settles it.

**The two Lua versions differ** (5.4.6 in the IME, 5.4.8 for `tests/`). Both are
5.4.x, so the language surface is the same, but the unit tests do not run on the
interpreter that ships the product.

## Verdict summary

| # | Verdict | Evidence |
|---|---|---|
| **S1** | **PASS** (life-or-death) | Under `fluid_editor`, confirming `今天有點累` with space and then typing `buguo` left the whole string in the underlined inline preedit. No committed text appeared in the box at any point during segment-by-segment selection |
| **S2** | **FAIL, as design §15.2 F4 predicted** | A comma committed `今天有點累不過，` to the application as plain text. The stock `symbols` preset defines it as `{commit: …}`, which calls `Context::Commit()` whatever the editor is |
| **S2 fallback (§5.3)** | **PASS** | With `,` `.` `?` `!` `;` `:` `^` redefined as plain string values under `punctuator/half_shape`, the comma joined the preedit and the draft kept growing past it: `今天有點累補過，tian qi hen hao` stayed one composition. The patch merges per key — `<` `>` `/` `$` `%` and the paired quotes keep their preset list/pair forms |
| **S3** | **PASS** (life-or-death) | `commit_text type: function`, and pressing F8 put `HELLO FROM COMMIT_TEXT` into TextEdit |
| **S4** | **PASS** | `set_property`/`get_property` are functions; round trip returned `v1` |
| **S5** | **PASS** | `Control+Shift+T` switched `spike_fluid` -> `luna_pinyin` -> `spike_fluid` -> `luna_pinyin`, one schema per press (`user.yaml` `previously_selected_schema`; the menu-bar label was not captured). The plan's Step 5 code had to be corrected first — see deviations |
| **S6** | **PASS** | A `lua_filter` wrapping the first candidate in `ShadowCandidate(cand, cand.type, cand.text, "✗ probe comment")` showed `1. 你好 ✗ probe comment`; the log recorded `S6 ShadowCandidate ok: true` |
| **S7** | **Renders fully** in the three apps tested; Slack not installed: unverified | A 33-character draft, left open. Terminal: shown in Squirrel's floating preedit (stock `no_inline: true`), one line, no truncation. WeChat: inline, underlined, caret at the end. Chrome address bar: all 33 characters displayed — see the caveat below |
| **S8** | **translate: P95 21 ms warm, 93 ms cold. apfel: unavailable on this machine** | Criterion (local P95 <= 800 ms) met by a wide margin; the synchronous route holds and `timeout_ms = 1500` stays. apfel starts and lists its model but answers every completion with HTTP 503 — `device not eligible` on this machine — so the translate-vs-apfel comparison cannot be run here. Detail below |
| **S9** | **PASS** | `io.popen curl: EXIT=7` — curl ran and its exit code was read back. 7 is "failed to connect", expected with no backend installed. The criterion is an HTTP response *or* an explicit exit code |
| **S10** | **PASS** | `require subdir: true child-ok` — `require("spike_pkg.child")` resolves |
| **S11** | **PASS with `MODE = prompt`** (life-or-death) | `segment.prompt` closes the loop in both states: the translation shows inline after the first Enter and the second Enter commits exactly it. `candidate` mode (design §6.2 as written) fails in both states. Detail below |
| **S12** | **Recorded — design §15.2 F11 confirmed** | Losing focus to another app or window commits the **raw key string**: a 33-character Chinese draft became 99 letters of pinyin, in TextEdit and in WeChat. A click elsewhere in the same box does the same in WeChat; TextEdit instead keeps the preedit as displayed. Switching the input source to ABC and back left the draft intact. Input to decision D2. Detail below |
| **S13** | **Holds below a hard ceiling of about 2.5 s** | No Enter reached any application at 1.5 s, so the synchronous model stands. Between 2.5 s and 3 s a system-level threshold is crossed: TextEdit then receives Enter as a newline and loses the draft; WeChat receives it as a newline in the input box and keeps a stale copy of the draft. Terminal stayed safe to 4 s. Keys typed during the stall always arrived, in order. Slack not installed: unverified. Detail below |
| **S14** | **Recorded** | After a confirmed Chinese segment: a URL with a scheme stays literal (Rime's `recognizer` URL pattern); an identifier's lowercase head is converted as pinyin (`handle` became `漢代了`) while the capitalised tail stays literal; opening the emoji picker takes focus and dumps the draft as raw pinyin, though the emoji itself arrives. Detail below |

**All three life-or-death items hold: S1, S3 and S11.** S11 holds only with the
`segment.prompt` display mechanism; the candidate mechanism of design §6.2 as
written does not close the loop.

## Expected vs seen

Design §15 stated what upstream source predicts. One line each.

| Check | Source reading said (§15.2) | Seen |
|---|---|---|
| S1 | pass — `FluidEditor` has `_auto_commit` off (F1) | pass |
| S2 | fail — the preset's `{ commit: … }` punctuation commits whatever the editor (F4) | fail; the plain-string fallback worked |
| S5 | pass — `select:` applies a schema (F2) | pass |
| S11 | candidate mode fails in both states on librime ≥ 1.11.2 (F5, F6, F7; §15.3) | exactly as derived, step for step; `prompt` (F9) closes the loop |
| R11 / S12 | deactivation commits the raw key string (F11) | yes, in TextEdit and WeChat |
| R15 | Caps Lock sets `kLockMask` on every key (F12) | yes — `mod=0x2` on Return |
| Properties vs `ctx:clear()` | untouched (F10) | survived |

No disagreement with the source readings. The version question F6 raised is
settled for this machine: librime 1.16.0 translates the trailing empty segment.

## Constants later tasks need

| Constant | Measured value | Consumer |
|---|---|---|
| `kNoop` / `kAccepted` | `2` / `1` — a processor returning `1` swallowed Enter and F8; returning `2` passed every key on | Task 9 |
| `key.release` | a **function** — the glue writes `key:release()`, not `key.release` | Task 9 |
| Return keycode | `65293` = `0xFF0D`, modifier `0` | Tasks 8, 9 |
| Plain letter keys | modifier `0` (`n i h a o` = 110 105 104 97 111) | Task 8 |
| Modifier masks seen | Super `67108864` = `1<<26`; release bit `1073741824` = `1<<30` | Task 8's modifier handling, R15 |
| `ctx:get_commit_text` | function | Tasks 7, 9 |
| `ctx:refresh_non_confirmed_composition` | function | Task 9 |
| **S11 display mechanism** | **`segment.prompt`** — set on `ctx.composition:back()`; shown inline in the preedit, never part of `get_commit_text()` | **Tasks 7 and 9; decision D1** |
| Enter with Caps Lock on | `mod=0x2` (`kLockMask`); passed through, it reached the application and replaced the marked text | Task 8 — mask to Shift/Control/Alt/Super before `decide` (R15) |
| libretranslate response field | `translatedText` (`{"translatedText":"Got it. I'll read it right away."}`) | Task 6 |
| Stall ceiling | the whole Enter-to-return path must stay **below about 2.5 s** (S13) | Tasks 5, 6, 9 — `timeout_ms` budget |
| **Context properties survive `ctx:clear()`** | `S4 survives ctx:clear: v1` | **Task 9 must clear session state explicitly** — confirms design §15.2 F10 by measurement |

## Deviations from the plan

**Step 2's code is missing `rime.lua`, and without it nothing runs.**
librime-lua resolves a component written `lua_processor@spike_probe` to a **Lua
global** named `spike_probe`, which must be defined in `rime.lua` in the Rime
user or shared data directory. It does not resolve the name as a file. With no
`rime.lua`:

- the component is created **without any error** — the Rime log has no `E` line
  at all;
- the Lua chunk is never loaded, so a probe that only writes from inside its key
  handler produces complete silence;
- the one diagnostic librime-lua emits (`rime.lua info: rime.lua should be
  either in the rime user data directory or in the rime shared data directory`)
  goes to stderr, which is invisible for a GUI process.

**Step 5's code appends a second top-level `key_binder:`** to a schema that
already has one (`key_binder: import_preset: default`). Run as written, it
deployed with no error, but the built schema's `key_binder` held one binding: the
second section had silently replaced the first, `import_preset` was gone, and
with it paging, Tab and the emacs keys — design §15.2 F3, reproduced inside the
spike. Step 4 had already avoided the same trap for `punctuator`. The corrected
form adds `bindings:` beside `import_preset: default` in the existing section;
built, it held 30 bindings with paging intact.

A second point for Task 10: `default.custom.yaml` patches the *default preset*,
which both schemas import, so the translation schema carries two
`Control+Shift+T` bindings — the preset's `select: spike_fluid` first, its own
`select: luna_pinyin` last. The schema's own, later binding is the one that took
effect. That was measured, but "switch back" then rests on binding order; a
single `select: .next` avoids depending on it.

For `rime.lua`, the fix used here:

```lua
-- ~/Library/Rime/rime.lua
spike_probe = require("spike_probe")
```

The plan is immutable once a task has started, so this is recorded here rather
than patched into `task-01-spike.md`. **Tasks 9 and 10 inherit the same trap**:
the three Lua components (`ime_translate_processor`, `_translator`, `_filter`)
will fail in exactly this silent way unless the installer also lays down a
`rime.lua` binding each namespace. Task 12 should write this into design §15.

**A useful discovery for the workflow**: Squirrel has an installer/control CLI —
`--install` / `--register-input-source`, `--enable-input-source`,
`--select-input-source`, `--reload` (Redeploy), `--quit`, `--build`, `--sync`.
`--reload` removes the need to click Redeploy in the menu bar by hand, and
`--quit` forces a fresh Lua state, which is required after editing a Lua file
because `require` caches the old chunk for the life of the process.

**Registering the input source needed a logout.** Squirrel was installed after
the login session began; the system enumerates `/Library/Input Methods/` at
login, so it was absent from the input-source list and `--install` /
`--enable-input-source` both returned success while changing nothing. A logout
and login fixed it.

## Findings for the design review

Listed, not decided. Each is evidence for an open decision or a candidate new
one; opening and closing decisions is the user's call.

**Evidence for the open decisions**

- **D1 (display and staleness)** — the evidence S11 was waiting for is in:
  `segment.prompt` closes the loop in both states; the candidate display of
  §6.1–§6.2 fails in both. With `prompt`, §6.1's "the draft is its own version"
  works as first intended.
- **D2 (focus loss)** — S12's evidence is in. Cmd+Tab, another window, and in
  WeChat even a click inside the same box turn the whole draft into raw pinyin.
  The chat-app chain matters most: the composition is then empty, so the user's
  next Enter passes through and sends the pinyin.

**Candidates for new open decisions**

- **The default backend does not run on this machine.** Design §9's default
  (`openai` adapter, `127.0.0.1:11434`, `apple-foundationmodel`) is apfel, and
  apfel is unavailable here. `translate` works and is fast (S8). What the default
  becomes — `translate`, a cloud tier, or another local model server — is open,
  and the §10.4 blind eval can no longer be translate-vs-apfel on this machine.
- **A hard ceiling on the whole stall, about 2.5 s** (S13). Above it the platform
  itself loses (TextEdit) or duplicates (WeChat) the draft, below Lua. The
  local `timeout_ms = 1500` fits; the budget must include spawn and parsing, and
  the cloud tier sits close to the line.
- **Keys the IME passes through while composing let the application overwrite
  the marked text.** Seen four times: Return after the stall threshold (S13),
  Return with `kLockMask` (R15), Control+Space (S12), keypad `/` and `.` (S14).
  In the translation schema a sentence-long draft is always open, so this is a
  standing risk, not an edge case.
- **Caps Lock clears the draft** (source reading of the live config:
  `ascii_composer/switch_key/Caps_Lock: clear`). Whether the translation schema
  overrides it.
- **Terminal is unreachable by default**: stock `app_options` start it in
  `ascii_mode`.

**Plan and design text that needs correcting** (found during execution; the
plan is immutable once the task has started, so these are for Task 12 or the
review):

- Step 2 and every later Lua component need a `rime.lua` binding, or they fail
  silently. Tasks 9 and 10's installer inherits this.
- Step 5 appends a duplicate `key_binder:`, which silently drops
  `import_preset` (F3).
- `default.custom.yaml`'s `key_binder/bindings/+` lands in *both* schemas via the
  default preset.

## Per-check records

### S11 — the Enter -> preview -> Enter loop

Run by the agent end to end from 19:37: keystrokes posted through System Events
(they travel the real input-method path — the probe logged them), the screen
captured with `screencapture -x`, which does not take focus, and TextEdit's
text read back over AppleScript. Probe code is the plan's Step 7, extracted
verbatim from `task-01-spike.md`, plus the `rime.lua` bindings above.

| Mode | State | After Enter 1 | Enter 2 | Verdict |
|---|---|---|---|---|
| `candidate` | A (all confirmed) | `FAKE ENGLISH` is the only candidate, position 1 | `draft=[今天有點累FAKE ENGLISH]` != `snap=[今天有點累]` -> **STALE, re-translates** | **fail** |
| `candidate` | B (last segment open) | `FAKE ENGLISH` at **position 4**, below `不過` / `補過` / `不果`; the translator had read `commit_text_now=[今天有點累buguo]` | `draft == snap` -> commits `FAKE ENGLISH` | **fail** — with design §6.2's third check the candidate is suppressed, so the user sees nothing and Enter 2 commits English never shown |
| `prompt` | A | preedit `今天有點累  -> FAKE ENGLISH`, underlined, no candidate window | `draft == snap` -> commits; TextEdit holds `FAKE ENGLISH` | **pass** |
| `prompt` | B | preedit `今天有點累bu guo  -> FAKE ENGLISH`; Rime's own candidate window stays open with `不過` highlighted | `draft=[今天有點累不過] == snap` -> commits `FAKE ENGLISH` | **pass** |

Source readings this run turned into measurements:

- **F5** — `get_commit_text()` includes the highlighted candidate: after Enter 1
  in candidate mode it read `今天有點累FAKE ENGLISH`.
- **F6** — on librime 1.16.0 the trailing zero-length segment *is* sent to the
  translators: `T input=[] seg=[17,17)`.
- **F6/F7** — inside `Query` the segment being filled has no menu yet: in State B
  the translator read raw pinyin (`今天有點累buguo`), not the highlighted
  candidate.
- **F9** — `segment.prompt` is rendered in the preedit and never read by
  `get_commit_text()`.
- **§15.3 State A**, exactly as derived. The probe committed on a *third* Enter
  only because its fake translation is a constant, so re-translating reproduces
  it. With a real backend the re-translation input is Chinese + the previous
  English, the output differs, and the loop does not converge.
- The Lua candidate's rank is **unstable**: position 1 in State A, position 4 in
  State B, alternating while typing with a stale phase.

Further rows, `prompt` mode only:

| Row | Action after the prompt shows | Result |
|---|---|---|
| 5a | type one letter | The prompt disappears (the segment is rebuilt); the draft survives plus the letter. The next Enter reads `今天有點累啊` != snapshot -> re-translates the edited draft. **The design's "the draft is its own version" (§6.1) works under `prompt`** — it failed only because the candidate display polluted the version |
| 5b | Esc, passed to the native chain | The **whole draft is cleared** and nothing is committed. So design §5.2's `result`-phase Esc must be intercepted by the processor, which clears only the prompt and the phase |
| 4 | mouse click on a candidate | not run: candidate mode is rejected, and no click tool was installed at the time |

### R15 — Caps Lock

- **Measured, with a synthetic flag.** A Return event posted with the Caps Lock
  flag while a draft was open reached the probe as `key=0xff0d mod=0x2` — the
  `kLockMask` bit, confirming design §15.2 F12. No processor in the stock chain
  accepted it; it reached TextEdit, whose newline **replaced the marked text**.
  The draft was lost and Enter was delivered. In a chat box that is a send with
  the message eaten.
- **Source reading, not observed.** The live config inherited by the translation
  schema has `ascii_composer/switch_key/Caps_Lock: clear` with
  `good_old_caps_lock: true`. Pressing the real Caps Lock key with a draft open
  therefore discards the draft before any Enter arrives.
- Both paths lose the draft. The register's "one-line fix in the glue" covers
  only the first. Whether the translation schema overrides `Caps_Lock` is a
  design decision.

### S8 — backend latency baseline

`translate` 0.1.1 from `arthur-ficial/tap`; the zh-en model was downloaded by the
user through System Settings -> General -> Language & Region -> Translation
Languages, after `translate --install zh-en` had failed with `Unable to
Translate` from the command line (design §12 R9, confirmed). apfel 1.11.0 from
Homebrew core.

| Measure | translate |
|---|---|
| Cold — first translation after the server came up | **93 ms** |
| Warm, curl `time_total`, 3 rounds x 5 sentences | P50 **15 ms**, P95 **21 ms**, max 25 ms |
| Warm, the plan's `bench.sh` (its clock includes a `python3` start-up) | 32-47 ms |
| The IME's own path: Lua `io.popen` -> `sh` -> curl, with one `python3` spawn for the clock | P50 38 ms, P95 43 ms |

| Sentence | translate output |
|---|---|
| `收到，我马上看` | Got it. I'll read it right away. |
| `哈哈哈可以，就这么定了` | Hahaha, okay, that's it. |
| `这个 bug 在 handleSubmit 里` | This bug is in handleSubmit |
| `文档见 https://example.com/docs` | See the documenthttps://example.com/docs — **the space before the URL is lost** |
| `今天有点累，不过进展不错 🎉` | I'm a little tired today, but it's progressing well 🎉 |

Output was identical in all three rounds. Identifier and emoji survived.

**apfel.** `apfel --model-info` reports `available: no (device not eligible)`.
Started correctly (`apfel --serve --port 11434`), the server answers
`GET /v1/models` with HTTP 200 and lists `apple-foundationmodel`, then answers
every `POST /v1/chat/completions` with **HTTP 503** `server_error` in about 22 ms.
Two consequences for Task 6: the adapter will classify every call as
`http_error`, and a health check that only probes `/v1/models` would report a
backend that cannot translate as up. apfel's own message blames Intel hardware;
which does not apply to the development machine. The actual cause,
established after the run: Apple does not make FoundationModels (Apple
Intelligence) available for this machine's device region, as the machine's own
eligibility record shows. The region is fixed in the hardware, so no setting
changes it, and there is no supported way to enable FoundationModels on this
Mac. The Translation framework behind `translate` is not gated by it, as S8
shows. Device and region details are left out of the published record.

**The plan's apfel command is wrong for 1.11.0**: `apfel serve --port 11434`
takes `serve` as prompt text and ignores `--port`; the flag is `--serve`.

### S13 — the host application during a synchronous stall

Probe: Step 7's processor in `prompt` mode with `SLEEP` set per run. Each run
typed `jintianyoudianlei`, confirmed with space, posted Enter, then posted
`abcde` 0.3 s into the stall. Leaks were judged byte-exactly from the document
after the run (TextEdit), from the caret position and `cat`'s echo (Terminal),
and from the input box (WeChat File Transfer chat).

| Stall | TextEdit | Terminal | WeChat |
|---|---|---|---|
| 1.5 s | safe | safe | safe |
| 2 s | safe | — | — |
| 2.5 s | safe (x2) | — | safe |
| 3 s | **Enter delivered as a newline; draft lost** (x2) | safe | **Enter delivered as a newline in the input box; stale copy of the draft left above the live one** |
| 4 s | **same as 3 s** (x3) | safe | **same as 3 s** |

What separates the two outcomes above the threshold:

- **TextEdit**: when the next key arrived, Rime's composition was already empty
  (`input=[]`) while the Context properties were intact — consistent with a
  `Context::Commit`/`Clear` triggered from the frontend. The newline replaced
  the marked text; nothing of the draft was committed. The same replacement was
  seen in the R15 run above.
- **WeChat**: Rime's composition survived, so the live draft reappeared on a
  second line under the stale one. Nothing was sent — Enter became a newline, not
  a send — but a second Enter committing a translation would now send the stale
  Chinese line with it.
- **Terminal** runs with Squirrel's stock `no_inline: true`: the client dropped
  only its placeholder marked text, never processed Enter, and the draft stayed
  whole in Squirrel's floating preedit.

**Derivation, not measured**: the threshold is the same in two unrelated apps,
so it is most likely the input-method reply timeout of the text-input system
rather than anything app-specific. The apps differ only in what they do with a
key the IME failed to answer in time.

**Consequences for the design** (for the design review, not decided here):

- The plan's pass line — no Enter reaches the application at 1.5 s — holds, so
  the synchronous model stands.
- The **whole** stall, not just the backend call, must stay under about 2.5 s:
  process spawn, curl, JSON handling and the Lua path all count. The local
  default `timeout_ms = 1500` sits inside it; the cloud tier's 0.5-2 s freeze
  (design §12 C3) is close to it.
- Crossing the threshold is worse than R12 anticipated. R12 feared a send; what
  was observed is **draft loss** (TextEdit) or **draft duplication** (WeChat).
  Both happen below Lua, so invariant 1 cannot cover them — only the ceiling can.

### S12 — focus loss with a 33-character draft

Draft: five segments confirmed with space,
`今天有點累不過天氣很好我們一起去公園散步吧然後喫點好喫的晚上再回家`, plus one open
segment (`x`). After each action one more key was typed to see whether it joined
the old composition.

| Action | TextEdit — what the box holds | WeChat — what the box holds | Draft editable afterwards |
|---|---|---|---|
| Cmd+Tab away and back (frontmost verified mid-switch) | `jintianyoudianleibuguo…huijiax`, the raw key string | the same raw key string | no — composition empty |
| Click into another window's text field and back | the raw key string | not run: same deactivation path as Cmd+Tab | no |
| Click elsewhere in the same text box | the preedit **as displayed** (Chinese plus the open segment's `x`) turned into plain text | the raw key string | no |
| Input source to ABC and back, through TIS | unchanged | unchanged | **yes** — the next key joined the old composition |

- The Cmd+Tab and other-window rows are design §15.2 F11 exactly: Squirrel's
  deactivation commits `get_input`. The Chinese is gone; only the pinyin is left.
- **The chain that matters in a chat app**: after the dump, Rime's composition is
  empty, so `decide` sees an empty draft and passes the user's next Enter through.
  The user presses Enter meaning "translate", and WeChat **sends the pinyin**.
- The input-source switch went through `TISSelectInputSource`, the same API the
  menu uses, but programmatically; the machine's keyboard shortcut for switching
  was not exercised.
- A first Cmd+Tab attempt left the draft intact — the switch had not actually
  happened (no frontmost check then). Discarded; the verified run is the row above.
- **Side observation**: on this machine Ctrl+Space is not an input-source
  shortcut. Pressed with the draft open, it reached TextEdit, which **replaced
  the whole draft with one space**. The same pattern as S13 and R15: a key the
  IME passes through while composing lets the app overwrite the marked text.

### S14 — typing mixed content into the draft

Each run: `jintianyoudianlei`, space, then the content. Final pass only — see
the harness note below for why two earlier passes were discarded.

| Input | Composition afterwards (`get_commit_text()`) | Typable into the draft? |
|---|---|---|
| `handleSubmit` | `今天有點累漢代了Submit` | **No.** The lowercase head is pinyin to Rime; only the part from the capital on stays literal |
| `https://example.com/docs` | `今天有點累https://example.com/docs` | **Yes.** Once `https:` is typed, the `recognizer` URL pattern takes the segment and keeps it literal; it runs before `punctuator`, so `:` `/` `.` are not converted |
| emoji via Ctrl+Cmd+Space | the picker takes key focus the moment it opens; the document then held `jintianyoudianlei` — the draft dumped as raw pinyin, S12's path — and the emoji was inserted after it | **No.** The emoji arrives; the draft does not survive |

Not tested: a URL without a scheme (`example.com/docs`), which the `recognizer`
pattern does not cover and which is likely to be split into pinyin and
full-width punctuation. For design §10.4 this means the identifier and emoji
categories of the blind eval are not reachable from the keyboard as the eval
feeds them; the URL category is, when the URL carries a scheme.

**Harness note — synthetic Shift.** Two earlier passes were discarded. System
Events posts a shifted character as a separate modifier change whose virtual key
code is 0, and Squirrel translated that into a phantom `a` with the Shift bit
(`key=0x61 mod=0x1`) before every shifted key. That turned `https:` into
`httpsa:`, which defeated the `recognizer` pattern. System Events also sent `/`
and `.` as keypad keys (`0xffaf`, `0xffae`), which the punctuator does not claim,
so TextEdit overwrote the marked text with them. The final pass posts each
shifted key as a single CGEvent carrying the Shift flag and uses main-keyboard
key codes for punctuation; its logs show neither artefact.

### S7 — long preedit, per application

| Application | Mode | 33-character draft |
|---|---|---|
| Terminal | floating preedit (stock `no_inline: true`) | one line in Squirrel's panel, no truncation; a placeholder underscore at the caret |
| WeChat | inline | full, underlined, caret at the end |
| Chrome address bar | inline | all 33 characters displayed. **Caveat**: the capture cannot resolve the underline, and it was taken after Chrome had stopped answering AppleEvents — a macOS Automation consent prompt (the terminal controlling Chrome) was pending — so it shows the composition from the first of two runs |
| Slack | — | not installed: unverified |

No flicker or caret misplacement was seen, but a still capture cannot show
flicker; that part stays with the compatibility matrix in Task 11.

### Compatibility facts found on the way

- **Stock Squirrel starts Terminal in `ascii_mode` with `no_inline: true`**
  (`squirrel.yaml` `app_options`). The translation schema is unreachable in
  Terminal until the user toggles to Chinese or the option is overridden. The
  spike overrode `ascii_mode` in `squirrel.custom.yaml`; Step 10 removes it.
- **A Lua syntax error in a component is skipped silently.** A probe written
  with an empty constant made the IME behave as plain `fluid_editor` — Enter
  committed the Chinese draft. Safe, since no text was lost, but a broken
  `ime_translate_processor.lua` would make translation vanish with no error.
- **A synthetic Return carrying the Caps Lock flag switched the input source to
  ABC** (the system's Caps-Lock-to-ABC switch for CJK input sources). A side
  effect of the test tool; recorded so it is not mistaken for a finding.

### Harness notes for the remaining checks

- **A screenshot tool that takes focus dumps the draft.** Snapzy's capture
  deactivated the input context; Squirrel's `deactivateServer` then emptied the
  composition. Observations must be taken without moving focus —
  `screencapture -x` does not.
