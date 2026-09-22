# Install and risks

Part of the design set — start at [overview.md](overview.md).

## 11. Installation

```
brew install --cask squirrel          # Squirrel is a cask, not a formula
brew install arthur-ficial/tap/translate   # the default backend (decision D4)
./scripts/install.sh                  # copy lua + schema + yaml into ~/Library/Rime;
                                      # install the backend LaunchAgent
# Add Squirrel as an input source in System Settings (one-off, manual),
# then Redeploy Rime for it to take effect
# Turn on Squirrel's inline_preedit
```

`install.sh` must handle: the `ime_translate/` subdirectory has to be preserved
(`require("ime_translate.state")` looks for `lua/ime_translate/state.lua`;
flattening breaks it); an existing user config is left alone and defaults are
only laid down when missing; the schema and `default.custom.yaml` belong to this
project and are backed up before being overwritten.

The default backend, `translate`, needs a one-off download of the zh→en model
through System Settings → General → Language & Region → Translation Languages.
Measured in the Task 1 spike: `translate --install zh-en` fails from the command
line, because the framework's download needs a confirmation UI. `install.sh`
cannot automate it; it can only check `translate --installed` and say what to do.

## 12. Risks

| ID | Risk | Mitigation |
|---|---|---|
| **S1** | **`fluid_editor` still commits early** → the draft is unreachable | First life-or-death spike criterion; falsified → back to design, evaluate B′ |
| **S3** | **`engine:commit_text()` unavailable or cannot commit arbitrary text** | Life-or-death criterion; falsified → A′ does not exist |
| S2 | Chinese punctuation commits directly. **Expected from source**: the stock preset defines `, . ? ; : ! ^` as `{ commit: … }`, which commits whatever the editor is ([upstream.md §15.2](upstream.md) F4) | Fallback in [architecture.md §5.3](architecture.md): redefine those marks as plain string values inside the translation schema, so they stay in the draft. Verified in the spike itself (Task 1 Step 4) rather than left for Task 10 |
| S7 | Long preedit breaks in terminals / Electron | Record per application; downgrade broken ones to a floating preedit |
| P1 | Synchronous block of N ms at the moment of Enter | Measured by S8; a local NMT can push N very low |
| **C3** | **0.5–2 s freeze on cloud** | Known cost, not a defect; marked "cloud" in the menu bar and log. The mitigation (pre-translation) is of unproven feasibility — see [backend.md §8.3](backend.md) |
| **C1** | **Privacy: the IME sees every character the user types** | Explicit `allow_remote` switch; local is the default tier |
| C2 | API key leak | Never written into `~/Library/Rime/`; goes through Keychain; shell construction uses `json.shq`, not `%q` |
| C4 | Cost and rate limits | One billed call per Enter; `rate_limited` is its own code; "no automatic retry in v1" needs rechecking for the cloud case |
| R4 | Translation quality insufficient (NMT skews formal) | The 30-sentence blind eval in [testing.md §10.4](testing.md); the three backend tiers back each other up |
| R6 | Electron (WeChat) quirks around IMEs | Named explicitly in the [testing.md §10.3](testing.md) matrix |
| R8 | Whether a LaunchAgent's background context can use Translation.framework is unverified | Measure; if not, attach to the user's Aqua session instead |
| R9 | The model download may have to go through the System Settings GUI | Documented as a one-off manual step |
| R10 | The Enter → preview → Enter loop did not close with the translation shown as a candidate — the draft read through `get_commit_text()` includes the very candidate used to display it. *Measured (S11)* | Closed by D1: the translation is shown through `segment.prompt`, which S11 measured closing the loop in both states. Detail §12.1 |
| **R11** | **Losing focus dumps the whole draft into the application as raw pinyin** — Squirrel does it, below anything Lua can see. *Measured (S12)* | S12: a 33-character draft became 99 letters of pinyin, in TextEdit and in WeChat. 001 Task 11's matrix saw the same in Chrome and Safari. Accepted as a documented cost by decision D2 (2026-09-22): deal with the draft before switching away. Detail §12.1 |
| R12 | What the host application does while the IME blocks for 1.5–4 s — Enter reaching a chat box would be send. *Measured (S13)* | No Enter reached any application at 1.5 s. Between 2.5 and 3 s a system threshold is crossed. `timeout_ms` defaults to 1500 and the config warns past 2500. Detail §12.1 |
| R13 | The costs of "the composition is the draft": editing model, draft length, whether mixed content can be typed at all, a user dictionary that never learns. *Measured (S14) + source reading* | S14 recorded what mixed content becomes. Feature 002 made mixed input typable (§5.5). The user dictionary still never learns: a stated cost. Detail §12.1 |
| R14 | API key and translated text visible in curl's argv through `ps`. *Source reading (of our own plan)* | Not addressed in v1. Detail §12.1 |
| R15 | With Caps Lock on, Enter was not intercepted (`decide` tested `modifier == 0`). *Measured (spike R15)* | Fixed in `decide` (Task 8): the Lock bit is dropped before any comparison. Detail §12.1 |
| R16 | Caps Lock with a draft in English mode, reached by a Shift tap (feature 002): the next letter would have replaced the whole draft. *Derivation* from F26 and the R15 measurement | **Closed by D7 (2026-09-22):** `Caps_Lock: noop` in the translation schema, schema change 9. That also closes 001 row 26's path. Task 6 row 25 is a gate: no text lost. Detail §12.1 |
| R17 | BackSpace into a locked segment reads what is left of it again in the current mode. In Chinese mode English shows as pinyin with candidates again; in English mode Chinese turns back into letters. Nothing is lost. *Derivation* from F23, agent-observed in Chinese mode (2026-09-22) | With the Enter way (§5.5) this is the edit path: BackSpace, then Enter locks the letters again. Task 6 rows 23–24 record it. Detail §12.1 |

Every row carries an evidence label — source reading, derivation, unverified or
measured; the `design-review` skill defines them. S1–R9 predate the labels and
are unmeasured unless a row says otherwise. **No row is a measurement until a
spike report or a smoke check says so.**

**Machine environment (measured 2026-09-07)**: macOS **26**,
arm64. Swift toolchain 6.3.3 (Command Line Tools; full Xcode not required).

> The machine is ≥ 26.4, so `TranslationSession`'s `.lowLatency` branch is
> reachable. That does **not** mean `.lowLatency`'s actual benefit has been
> verified — the probe in [evidence.md §14.2](evidence.md) only proved the
> framework runs and the language pair is supported; the model was not yet
> downloaded at that point, and real zh→en success rate, cold/warm latency and
> quality are still unmeasured. **Vendor performance claims, estimated latency,
> and this project's own measurements must be recorded separately.**

### 12.1 Detail for R10–R15 (design review, 2026-09-20)

Found before Task 1 started, by reading upstream source; the readings themselves
are [upstream.md §15](upstream.md). The register above stays scannable; this is
where the reasoning lives.

**R10 — the Enter loop.** §6.1 takes the draft from `get_commit_text()`, which
includes the highlighted candidate of every open segment (§15.2 F5); §6.2
displays the translation as a candidate in that same menu. Derived in §15.3:
with the draft fully confirmed, the second Enter re-translates instead of
committing, and on old librime nothing is displayed at all; with the last
segment open, nothing is displayed and the second Enter commits English the user
never saw. Headless tests cannot see it — the fake context's commit text is
fixed. S11 runs the loop with a fake translation, in both states and with both
display mechanisms. The candidate direction is `segment.prompt` (§15.2 F9): not
part of the commit text, not selectable by digit or mouse, gone as soon as the
segment is rebuilt. The design change waits for S11
([decisions.md §13](decisions.md), D1), and D1 blocks Tasks 7 and 9.

*Update (D1 closed, 2026-09-21).* S11 measured both halves: the candidate display
failed in both states exactly as derived, and `segment.prompt` closed the loop in
both. Design §6.1–§6.2 and §6.4 now show the translation, and the error reason,
through the prompt; the translator and filter components are gone. What is left
is §6.2's residual — a stale prompt after a mouse edit, until the next key — and
the unmeasured rows §6.4 lists.

**R11 — focus loss.** Squirrel's `deactivateServer` → `commitComposition`
commits the raw key string and clears the composition (§15.2 F11). An ordinary
composition is a few characters and nobody notices; here the composition *is*
the message, and Cmd+Tab in the middle of writing one is routine. The Chinese
draft is gone. It happens below Lua, so invariant 1 cannot cover it. S12 records
what actually lands, per application; then D2 chooses between a documented cost
and a Squirrel patch. No Squirrel setting for it was found in
`SquirrelInputController.swift`; its configuration files were not searched.

**R12 — the host during a stall.** S8 times the backend from a shell; nothing
measures a 1.5–4 s stall inside the frontend's event handler. If the text-input
system has a reply timeout, Enter could be treated as unhandled and reach the
application — in a chat box, that is send. Unverified in both directions. S13
blocks on Enter for 1.5 s and 4 s in WeChat, Slack and Terminal. Matrix item 10
already covers keys typed during the wait.

**R13 — the composition as draft.** BackSpace under `fluid_editor` reopens the
previous selection as pinyin rather than deleting a character (§15.2 F1); moving
the caret back before a confirmed segment voids every selection after it; there
is no mouse positioning, no paste and no undo inside the draft. All of it grows
with draft length, and all of it sits badly with "typing habits not narrowed"
([requirements.md §2](requirements.md)). Whether an identifier with capitals, a
URL or an emoji can be *typed into* a composition is unverified — the §10.4 eval
feeds them through curl (S14). Translation-mode input never teaches the shared
user dictionary (§15.2 F10). Apart from S14 this is cost to state rather than to
fix: consider narrowing the promise to "one sentence per Enter", and
`max_chars` = 2000 is far past what a Rime composition will realistically hold.

**R14 — argv.** The API key and the text being translated sit in curl's argv,
and in the `sh -c` argv above it, for the life of each request, readable by any
local process through `ps`. Low on a single-user machine, but out of step with
the care taken in [backend.md §7.3](backend.md). If it is ever addressed:
`security … -w` piped into `curl -K -` keeps the key out of every argv, and the
body can go through a 0600 temp file.

**R15 — Caps Lock.** Squirrel sets `kLockMask` on every key event while Caps Lock
is on (§15.2 F12), and `decide` tests `modifier == 0`, so Enter falls through to
the native chain. Where it ends up — committed Chinese, or Enter reaching the
application with the draft still open — is unverified; the S11 probe logs the
modifier and passes such an Enter through, so it gets observed. The fix is one
line in the glue: keep only the Shift / Control / Alt / Super bits before calling
`decide`.

*Update (Task 8).* Measured by the spike (R15): the Enter carried `mod=0x2`,
passed through, and the application's newline replaced the marked text. The mask
went into `decide` instead of the glue, where it is unit-tested: `decide` reads
only the Shift / Control / Alt / Super bits, so the glue passes `key.modifier`
raw. Whether a real Caps Lock press can leave a draft open for such an Enter is
a *source reading*, not observed: the inherited `Caps_Lock: clear` discards the
draft on the press itself — the spike report's second R15 path, which this fix
does not touch and which is still open. A schema that sets `Caps_Lock` to `noop`
or `inline_ascii` would close that path and open this one, which is now safe.

**R16 — Caps Lock after a Shift tap (feature 002).** Derived in
[upstream.md §15.5](upstream.md) from F26:
- **The press.** With `good_old_caps_lock` and `ascii_mode` already on,
  `ProcessCapsLock` rejects the Caps Lock press to the application. It neither
  switches nor clears, so the draft stays.
- **The next letter** carries the Lock bit and is rejected to the application
  too. The spike's R15 measurement saw a rejected Enter's newline replace the
  marked text, so the letter replaces the whole draft.

001's path was the press itself clearing the draft, in Chinese mode (smoke
row 26). 002 adds this one, and makes it likely: English mode inside a draft is
where Caps Lock gets pressed.

`Caps_Lock: noop` skips `ProcessCapsLock` entirely. Squirrel then sends
capitals (F26), which reach the draft through `ascii_composer` in English mode
and through the `uppercase` pattern in Chinese mode. The price is that Caps Lock
no longer switches to English. That is the user's call: decision D7.

**R17 — BackSpace across a lock (feature 002).** Derived from F23.
1. The first BackSpace after the lock deletes nothing: it reopens the locked
   segment with its candidates.
2. The next deletes a character, and the rest of the segment is segmented
   again under the current mode.

What commits is what is shown, so it is a display surprise, not lost text. The
workaround is a tap before editing: it locks the reopened segment again, in
its own mode. Having the processor switch the mode to match a reopened segment
would remove the surprise. That is a design change, not made.

*Update (2026-09-22).* R16 is closed by D7 (`Caps_Lock: noop`). R17 was seen by
the agent in the Enter-way spike. `jintian`␣ `readme`⏎ BackSpace changed
nothing on screen, and the second BackSpace showed `re a d m` as pinyin, with
candidates. Under the Enter way the user presses Enter again to lock it: an
edit path, not a surprise.
