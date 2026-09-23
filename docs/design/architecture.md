# Architecture

Part of the design set — start at [overview.md](overview.md).

## 3. Plan selection

### 3.1 Chosen: Plan A′ — separate schema + fluid_editor + self-owned commit

Build the translation IME as a **separate Rime schema** `luna_pinyin_translate`,
side by side with the normal `luna_pinyin`, sharing its dictionary and user
dictionary:

- **`fluid_editor` replaces `express_editor`.** fluid_editor does not
  auto-commit — selecting a segment only confirms that segment; the whole
  sentence stays in the composition. **Rime's composition is itself the Chinese
  draft buffer; we do not build one.**
- **Committing the translation goes through `engine:commit_text(translation)` +
  `ctx:clear()`**, bypassing candidate selection and bypassing the segment
  concatenation in `Composition::GetCommitText()`.
- **State hangs off `Context` properties**, isolated per session.
- `Ctrl+Shift+T` goes to Rime's native `key_binder` `select:`; Lua needs no
  toggle logic.
- Normal Chinese input keeps using the original schema, **entirely unaffected** —
  this is the biggest advantage a separate schema has over an option toggle.

**Governing principle: display and commit are fully separated.** The
translation is shown through the last segment's `prompt`, which nothing ever
commits, and the processor alone owns committing. Both fatal defects of the
original Plan A came from letting a candidate carry both responsibilities — and
spike S11 measured a third: a translation shown *as* a candidate changes the very
draft it is checked against (§6.1, D1).

### 3.2 Alternative: Plan B′ — Lua-owned draft string

The processor swallows every key, accumulates the Chinese itself, and clears the
composition after each input. Maximum control, but preedit rendering, cursor,
backspace and candidate interaction all have to be rewritten — half an IME
frontend, in Lua. **A′ reaches the same place using Rime's existing composition,
so B′ is unnecessary.**

### 3.3 Fallback: Plan C′ — fork Squirrel

The native ObjC/Swift layer owns the draft, which unlocks async translation and
a custom bubble UI. Highest ceiling on experience, but the fork needs
maintaining forever.

> `Translation.framework` on macOS 26 offers a headless
> `TranslationSession(installedSource:target:)` ([evidence.md §14.2](evidence.md)),
> so translation can be compiled straight into the ObjC/Swift layer with no
> external process and no IPC — C′ costs less than first estimated. That does
> **not** lower its maintenance cost; it stays a fallback, not a preference.

### 3.4 Ruled out: side-car hotkey + Accessibility API

It cannot read the input box in WeChat, terminals and similar, which conflicts
with the everywhere-coverage requirement.

### 3.5 Ratchet rule

In the spike ([testing.md §10.2](testing.md)), **S1 (fluid_editor does not
auto-commit) or S3 (`engine:commit_text` is usable) falsified ⇒ Plan A′ does not
exist.** Return to design and re-review, evaluating B′ first rather than jumping
to C′.

> **No "if it fails, fork Squirrel" false dichotomy.** Even after a fork, draft
> ownership is still an open problem and a draft buffer still has to be
> designed; and before forking there is a large unexplored space in dedicated
> schemas and commit-behavior adjustments.

## 4. Architecture

### 4.1 Components

| Component | Responsibility | Form |
|---|---|---|
| Squirrel | IME host: key events, candidate window, committing | `brew install --cask squirrel`, off the shelf |
| `luna_pinyin_translate.schema.yaml` | **New**: the translation schema, paired with `luna_pinyin_simp`. `fluid_editor`; dictionary and user dictionary point at `luna_pinyin` (shared); one lua component, the processor, inserted first; `ascii_composer`'s Shift switch keys are `noop` (see §5.2), and so is `Caps_Lock` (D7, §5.5); the script switch is `luna_pinyin_simp`'s `zh_simp`, reset to Simplified (see the note below). Feature 003: three notice switches, hidden from the switcher menu, whose labels are the backend-switch notices (§5.6) | This project |
| `default.custom.yaml` | Two things: append the translation schema to `schema_list`, keeping the stock list; bind `Ctrl+Shift+T` to switch into it (the schema binds the way back) | This project |
| `ime_translate_processor.lua` | **Sole owner of committing and of the display**: take draft → call backend → write the translation or `✗ reason` into the last segment's `prompt` → `commit_text` → `ctx:clear()`. Feature 002: Enter on unselected pinyin locks it as the letters typed; Space with nothing unselected adds a literal space; on a Shift tap, lock the current segment, then switch Chinese ⇄ English (§5.5). Feature 003: switches the backend slot and turns on a notice switch; Enter translates with the active slot (§5.6). Feature 004: the switch is a lone tap of Right Option | Thin glue |
| `ime_translate/decide.lua` | Pure-function key decisions, testable headless. **No toggle branch** (schema switching belongs to native key_binder). Feature 002: Enter on unselected pinyin → lock it as letters; Enter on a draft with no Chinese commits it as is; Space with nothing unselected → a literal space. Feature 003 had `Ctrl+Shift+B` → switch the backend; feature 004 removed it, and the key is native again | Pure function |
| `ime_translate/shift_tap.lua` | **Feature 002.** Pure: tells a lone Shift tap (left or right, pressed then released within 500 ms with no other key in between) from Shift used as a modifier. **Feature 004:** the same rule for a lone Right Option tap, through a tap descriptor. Its state is kept by the caller, in Context | Pure function |
| `ime_translate/session.lua` | **New**: read/write wrapper over Context properties + draft snapshot comparison + the prompt text for the current phase | New |
| `ime_translate_shared.lua` | Process-wide, never per session: the config, the Keychain keys, and (feature 003) the active backend slot, read with the config and written to `ime_translate.active` on every switch (§5.6) | Module singleton, by design (§6.1) |
| `state.lua` / `config.lua` / `backend.lua` / `json.lua` | Phase constants and error-code strings (**holds no state object**, see §6.1), config, backend adapters, JSON | — |
| Translation backend | Translation inference | Local resident HTTP service (LaunchAgent) **or** a cloud API |
| Keychain | Stores the cloud API key | `security` command, read once at startup |

> **The draft's script (D5, 2026-09-21; amended the same day).** `luna_pinyin`'s
> dictionary is Traditional; only the simplifier makes the output Simplified.
> The user's daily schema is `luna_pinyin_simp`, whose simplifier reads the
> option `zh_simp` with `reset: 1`. The translation schema pairs with it and does
> the same: **Simplified whenever the schema loads**, switchable for the session
> with `Ctrl+Shift+4` or the switcher menu, not saved — `zh_simp` is not in
> `default.yaml`'s `switcher/save_options` ([upstream.md §15.4](upstream.md)).
> D5 first closed as "`simplification` without `reset`"; under the pairing that
> would have made every session that starts in the translation schema
> Traditional. The script decides what `Shift+Enter` commits, what the error
> fallback commits and what the backend receives as `zh`.

### 4.2 Data flow

```
user types pinyin ──► speller/translator (native) ──► composition
   │                                      (= Chinese draft, visible as inline preedit)
   │
   ├─ digit/space selection ──► selector confirms segment ──► draft advances,
   │                                                          fluid_editor does not commit
   │
   └─ Enter ──► ime_translate_processor intercepts (kAccepted, never passes through)
                  │
                  ├─ take the whole draft, store it as snapshot ime_translate.draft
                  ├─ call backend.translate synchronously (blocking, see backend.md §8.2)
                  └─ set phase = result / error, write the translation or ✗ reason
                     into the last segment's prompt (shown in the preedit)
                        │
                        ├─ Enter again    ──► engine:commit_text(translation) + ctx:clear()
                        ├─ Esc            ──► clear display back to idle, draft stays as-is
                        ├─ Shift+Enter    ──► engine:commit_text(Chinese draft) + ctx:clear()
                        └─ any other key  ──► void the translation back to idle, then pass through
```

### 4.3 What this architecture fixes

| Defect | How A′ handles it |
|---|---|
| Segment selection commits early, so the whole sentence is unreachable | `fluid_editor` does not auto-commit; the draft stays intact in the composition |
| Enter's commit semantics depend on `express_editor`'s `CommitRawInput` binding | Enter is never passed through and no default binding is relied on; the processor calls `commit_text` itself |
| The whole translation is stuffed into one segment and concatenated with others | The translation never becomes a candidate: it is shown through `segment.prompt`, which `GetCommitText()` never reads, and committed by the processor alone |
| Module-singleton state shared across input sessions | State lives in `Context` properties, per session |
| Failing to reset after committing breaks translation from the second sentence on | `commit_text` and the reset happen in the same event — no "reset on the next event" ordering trap |

**Residual**: whether Chinese punctuation is still routed straight out by
`punctuator` / `punct_segmentor`. That is S2 in
[testing.md §10.2](testing.md); the fallback is §5.3 below.

**Not fixed by this architecture, and outside Lua's reach**: on losing focus,
Squirrel itself commits the composition's raw key string to the application
([risks.md §12](risks.md) R11).

## 5. Interaction and key handling

### 5.1 Schema switching

`Ctrl+Shift+T` → `key_binder`'s `select:` switches between `luna_pinyin_simp`
(the user's daily schema) and `luna_pinyin_translate`. The forward binding sits
in the default preset, so it works from any stock schema; the way back always
leads to `luna_pinyin_simp`. The current schema name shows in the menu-bar input
menu; that is native Rime behavior.

Switching schemas rebuilds the engine and context, clearing draft and state with
it — which is correct: switching away means abandoning the current draft. Caps
Lock is not used.

**Which schema a new session starts in (corrected 2026-09-21).** An earlier
version said "the normal schema is the default at login". Not so: librime starts
every new session in `var/previously_selected_schema` from `user.yaml` (source
reading, [upstream.md §15.2](upstream.md) F16). Task 10's smoke row
16 saw a new document open in the translation schema. After one `Ctrl+Shift+T`,
every new input box and every restart begins in the translation schema until the
user switches back. With the local backend nothing leaves the machine; with a
cloud backend an Enter meant for a newline would send the sentence to the vendor.
**Decided (D6, 2026-09-22): kept.** New sessions start in the previously
selected schema, librime's own behaviour; the user chose not to force the
normal schema ([decisions.md §13](decisions.md)).

### 5.2 Key table (inside the translation schema only; the normal schema is fully native)

| Key | `idle` | `result` | `error` |
|---|---|---|---|
| **Enter** | draft non-empty → intercept, translate. Feature 002: unselected pinyin left → it becomes the letters typed, locked in the draft, nothing committed; nothing unselected and no Chinese in the draft → `commit_text(draft)` + `clear()`, no backend call | `commit_text(translation)` + `clear()` | translate again (feature 005; `Shift+Enter` commits the Chinese) |
| **Shift+Enter** | `commit_text(Chinese draft)` + `clear()` (skip translation) | same | same |
| **Esc** | native (clears composition) | discard translation, back to `idle`, **draft left intact** | same |
| **Space**, **Shift+Space** (feature 002; the processor takes them only with a draft open and nothing unselected) | a literal space in the draft; with unselected pinyin, native (selects) | void the translation, then a literal space | same |
| **Right Option tap** (feature 004; alone, released within 500 ms) | switch the backend slot (local ⇄ cloud) and show a notice; the draft, if any, stays | same — the Option press has already voided the translation, and the next Enter translates with the other backend | same |
| **Shift tap** (feature 002; left or right, alone) | draft open: lock the current segment, then switch Chinese ⇄ English; no draft: switch only | same — the Shift press has already voided the translation | same |
| **everything else** | pass through natively | **void the translation back to `idle` first, then pass through** | same |

`Shift+Enter` is a required escape hatch. Once the IME owns the draft there must
be a key meaning "don't translate this one, just commit the Chinese" —
otherwise the only way out is turning translation off, by which point half a
sentence of draft has nowhere to go.

**The caret (Task 9 review, 2026-09-21, the user's decision).** With the caret
inside unconverted input, librime composes only up to the caret, so
`get_commit_text()` stops there while the rest stays on screen
([upstream.md §15.2](upstream.md) F15, a source reading). Enter and Shift+Enter
with the caret anywhere before the end therefore only move it to the end, and
the next press acts on the whole draft, now on screen. Native Return also ends
with the caret at the end, but confirms the highlighted candidate first; this
rule recomposes instead, so a non-default candidate highlighted before the caret
falls back to the default — visible before the next press, never committed
unseen. At the start the engine already composes the whole input, so there the
rule costs one extra press. "Draft non-empty" in the table means the input is
not empty, which is what `ctx:clear()` removes.

**Shift switches nothing in the translation schema (2026-09-21, found in use;
the user's fix).** `ascii_composer` treats a Shift released with no key in
between as a tap that toggles English, and it resets that state on any other key
*it sees* ([upstream.md §15.2](upstream.md) F18, a source reading). With the processor first, the Enter of Shift+Enter
was taken before `ascii_composer` saw it, so every Shift+Enter left the IME in
English.

The schema therefore sets `ascii_composer/switch_key/Shift_L` and `Shift_R` to
`noop`, and the processor stays **first**. Moving it behind `ascii_composer`
was tried and withdrawn: `ascii_composer` rejects keys to the application ahead
of it — an Enter carrying the Lock bit after Caps Lock in inline English
(Task 10 review, round 3, a derivation) — and that is spike R15's lost draft.

Until feature 002, Shift did not switch to English in this schema.
- Rime's own `inline_ascii` held English only as the draft's tail anyway: see
  the smoke report, "Mixed Chinese and English in one draft".
- **Caps Lock** was the other way into English, and with a draft open it
  discarded the draft (`clear`). Since feature 002 it is `noop`: it only types
  capitals (D7, §5.5).
- **`Ctrl+Shift+T`** leaves the schema and discards the draft (§5.1).
- Feature 002 gives the Shift tap back, handled by the processor (§5.5).

**Measured by the user, 2026-09-21:** after Shift+Enter the IME stays in
Chinese, and a lone Shift tap does nothing.

**Esc right after a no-key edit (same review and decision).** When check 2
(§6.2) fires on an Esc press and a draft is left — the draft changed through
the mouse, with no key event, while the prompt may still be on screen — the Esc
is taken as in `result`: the prompt goes, the draft stays. Passed on, it would
reach the native `CancelComposition` and wipe the draft (S11 row 5b). If the
edit had already removed the prompt, that Esc does nothing visible and the next
one reaches the native chain; nothing is lost.

### 5.3 Chinese punctuation

**S2 failed, as the source predicted** (spike, 2026-09-20). With the stock
preset, a comma committed the whole draft to the application.
- **The fix.** The translation schema redefines the committing marks
  (`, . ? ! ; : ^`) as **plain string values**: `',' : '，'` rather than
  `',' : { commit: '，' }`. It does so in `half_shape` and in `full_shape`
  (schema change 4).
- **The result.** The mark stays in the draft: visible in the preedit, and
  sent to the translator with the rest of the sentence.
- **Measured.** The spike's fallback check passed, and so did 001 Task 10's
  smoke rows 3 and the full-width row.

The earlier version of this section held two branches, pending S2. The
unused one, "S2 passes: nothing special needed", is gone.

**Why the source predicted it**
([upstream.md §15.2](upstream.md) F4). A `{ commit: … }` definition calls
`Context::Commit()` whatever the editor is, and that is the form `symbols.yaml`
— the preset `luna_pinyin` imports — uses for `, . ? ; : ! ^`. A plain string
value instead confirms the current selection, which under `fluid_editor` only
advances the composition.

> The fallback first written here — map the mark to a space, or swallow it, via
> `{ commit: " " }` — was wrong twice over. Any `commit:` definition still
> commits the whole draft, which is the very thing being avoided; and the YAML
> patched `full_shape` while the default shape is `half_shape`. It also gave up
> more than it needed to: "the only cost is not seeing the comma" is a cost the
> string form does not pay. Corrected in the 2026-09-20 review
> ([decisions.md §13](decisions.md)).

### 5.4 `busy` downgraded to unreachable

While blocking synchronously, librime is single-threaded and receives no keys,
so `busy` cannot be observed. v1 keeps the enum value but marks it unreachable;
`should_intercept_return()` does not test for it. It regains meaning only if an
async path is taken later.

> **The candidate window cannot be repainted while the same thread is blocked**,
> so there is no two-stage "translating…" hint. This is not a thing to verify;
> it does not hold logically. After Enter it is "freeze for N ms → translation
> appears".

### 5.5 Mixed Chinese and English (feature 002)

**What.** English words typed inside a Chinese draft stay literal, and Enter
translates the whole sentence with them kept: `用git提交README文件` →
`Use git to submit the README file`.

**How — the Enter way** (the user's habit, decided 2026-09-22). As in the
macOS Pinyin IME, type the letters and press Enter; they stay as typed.
- **Enter with unselected pinyin left.** Everything not yet selected becomes
  the letters typed, locked into the draft. "Not yet selected" means the
  composition's confirmed position is short of the input's end. Nothing is
  committed and nothing is translated.
- **Enter with nothing unselected** translates, as in 001. A draft with no
  Chinese commits as is.
- **Space or Shift+Space with nothing unselected** adds a literal space to
  the draft. With unselected pinyin, Space selects, as it natively does.
  Natively, Space with nothing left to select would commit the whole draft
  untranslated (`Editor::Confirm`, F27). So would Shift+Space, which
  `fluid_editor`'s key map falls back to Space (002 Task 7 review).
- **In English mode** (the Shift tap) the open part is letters already, so
  nothing counts as unselected. Enter translates at once, or commits a draft
  with no Chinese as is. Whether to translate depends on the draft's content,
  never on the mode (the user's decisions, 2026-09-22).
- **A sentence**, then: select the Chinese as usual, press Enter after each
  English word, and press Enter once more to translate —
  `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎.
- **Capitals typed with Shift** are already letters, through the recognizer's
  `uppercase` pattern; Enter locks them the same way.

**How — the Shift tap, a supplement.** In Chinese mode a digit selects a
candidate, so English with digits or punctuation (`v2.0`) needs English mode.
- **Switching.** A lone tap of either Shift switches between Chinese and
  English, as in the system IME. In the translation schema, `ascii_composer`'s
  own Shift switching is off (schema change 8, §5.2), so the processor owns the
  tap.
- **A tap** is `ascii_composer`'s own rule (F18): a Shift press and its release
  less than 500 ms apart, with no other key between. The clock is librime-lua's
  `rime_api.get_time_ms()` (F22). Without it, any hold counts.
- **With a draft open.** Every printable ASCII character goes into the draft,
  space included: `ascii_composer` pushes it into the input (F19).
- **With no draft.** English letters go straight to the application
  (`ascii_mode`, native).
- **Locking.** On each tap with a draft open, the processor first locks the
  current segment by confirming its selection, and only then switches. The
  Chinese keeps the conversion on screen, and the English keeps its letters.
- **The mode after a commit** stays as it was (the user's decision). It
  changes only on a tap. The mode lives in the Rime session, and Squirrel makes
  one per input controller (F24). So another document or app starts in the
  schema's reset mode, Chinese, or in English where `app_options` say so.

**Mechanism.**
- **Enter.** The processor clears what is not confirmed, puts one bare segment
  over it, and confirms that segment. A segment with no candidate is confirmed
  as raw input (F20), and `get_commit_text()` takes its input. The mode never
  changes, so Squirrel shows no notice (F24).
- **Space.** The processor pushes a space into the input and confirms it the
  same way.
- **The tap.** The processor confirms the current selection, then switches
  `ascii_mode`. The order matters. `set_option` recomposes everything not yet
  confirmed in the new mode, and a confirmed segment is not translated again
  (F20). Under `fluid_editor` a confirmation never commits.
- **No translator is added.** An earlier version of this section added a
  raw-candidate translator. It rested on the belief that a segment with no
  candidate cannot be confirmed, which the source contradicts (F20), and D8
  dropped it.

**Evidence.** Throwaway spikes, both observed by the agent (TextEdit readback
and window screenshots), never by the user (decisions.md):
- **2026-09-22, the Enter way:**
  - `jintian`␣ `readme`⏎ `haode`␣ ⏎ ⏎ gave the draft `今天readme好的`, then
    `Today’s readme is good`.
  - `qing`␣ `pull`⏎ ␣ `request`⏎ ⏎ ⏎ gave `请pull request`, then
    `Please pull request`.
  - `readme`⏎ alone, and `jintianreadme`⏎ with nothing selected, both stayed
    literal.
  - Shift-typed `README` stayed literal.
  - A Space after a selection added a space.
- **2026-09-21, the Shift tap.** F12 stood in for the tap. Locking and then
  switching worked:
  - after a selection
  - without one: `今天readme好的`
  - with a space inside: `请pull request好的`
  - two English words in one sentence

  Switching first did not work: `readme` became `热爱多么`.

**Edges.**
- **The caret inside the input.** The first Enter or tap only moves the caret
  to the end (§5.2). Space there always has something unselected, so it
  selects, natively.
- **Enter on pinyin meant as Chinese** turns it into letters: to translate,
  select first (the user's decision).
- **BackSpace into a locked segment.** The first press reopens it, with
  nothing changed on screen. The next one deletes a character, and the rest is
  read again in the current mode. In Chinese mode it shows as pinyin with its
  candidates again (agent-observed), and Enter locks it again (R17).
- **Shift used as a modifier** (Shift+Enter, Shift+letter) is never a tap: the
  processor sees every key between the press and the release.
- **Shift held 500 ms or more** is not a tap.
- **Shift+click.** Squirrel receives no mouse events (F21), so a Shift+click
  released within 500 ms is a tap, as it is for `ascii_composer`.
- **A highlighted candidate shorter than its segment**, then a tap: only what
  it covers is locked (upstream §15.5).
- **`Control+Shift+2`**, the preset's `ascii_mode` toggle, switches without
  locking (upstream §15.5). The Shift tap is the switch that locks.
- **Caps Lock** is `noop` in the translation schema (D7, schema change 9). It
  only types capitals, which reach the draft as letters in either mode. The
  inherited `clear` discarded the draft (001 smoke row 26). After a tap it
  would also have let the next letter replace the draft (R16).

**Observed, 2026-09-22** (Task 6, [smoke-report-002.md](../smoke-report-002.md)):
- **The Enter and Space rules**, the caret rule for Enter, BackSpace across a
  lock and Shift+Space were run row by row, by the agent.
- **The Shift tap, Caps Lock, WeChat and the 👁 rows** were confirmed by the
  user as a whole ("no problem"), not row by row.

**Still not measured row by row:**
- the exact 500 ms edge, and whether `get_time_ms` is the clock actually in
  use (F22 found only its name in the installed binary)
- digits and ASCII punctuation typed in English mode
- two taps with nothing typed between them
- how long English runs translate

### 5.6 Switching the translation backend (feature 003)

**What.** Two backends are configured side by side: a local one and a cloud
one. A lone tap of **Right Option** switches between them: the cloud where the
network is good, the local `translate` where it is not. The user chose a key
alone, with no automatic fallback (2026-09-22).

> **Feature 005 adds the fallback (2026-09-23, the user's decision).** When
> the cloud slot fails, the same Enter asks the local slot, and a local
> translation shows as `  ☁✗ -> …`. Never the other way: a local failure is
> never sent to the cloud. Details in [backend.md §8.1](backend.md).

> **Feature 004 replaced `Ctrl+Shift+B` (2026-09-22).** The user found that
> `Ctrl+Shift+B` switched only with a draft open. That was seen by the user; the
> app was not recorded, and TextEdit switched with no draft in 003's smoke G1.
> - **Why it happens** (derivation, not measured per app). Squirrel hands every
>   key without Command to Rime, draft or not (F21, `handle(_:client:)`). So the
>   key is lost before Squirrel: an application may take a Control combination
>   as its own when nothing is being composed. A terminal sends it on as a
>   control character; Terminal did that to a posted `Ctrl+Shift+2`.
> - **The fix.** A lone modifier tap travels as a flag change, the path the
>   Shift tap already uses (F21). Squirrel tells Right Option from Left Option
>   (F30).
> - **The user's choices:** Right Option alone, with `Ctrl+Shift+B` removed and
>   given back to the applications; keyboard only, with nothing done about the
>   mouse.

**The two slots.** The config holds two backend slots ([backend.md §9](backend.md)):
- **local**: the keys with no prefix, exactly as before 003. The default is
  `translate`.
- **cloud**: the same keys with a `cloud_` prefix. There is no cloud slot
  unless `cloud_backend` and `cloud_base_url` are both set (D9).

The names say what the user means by them; nothing checks that the local slot
is really loopback. What is checked is the trust tier, per slot (§7.2).

**The switch.**
- **A lone tap of Right Option**, in every phase, with or without a draft.
  - **What counts as a tap.** Right Option is pressed, then released within
    500 ms, with no other key in between and no Shift, Control or Command
    held. It is the Shift tap's rule (§5.5), through the same pure module.
  - **What does not count.** Left Option, and Option used as a modifier
    (Option+letter), are not taps.
  - **Outside the translation schema** the processor does not run, and the tap
    does nothing.
- **A translation or an error on screen is voided first**, as by Esc: the prompt
  goes and the draft stays. The Option press voids it as any key does (the
  catch-all), and the tap then switches. The next Enter translates with the
  other backend, so a poor local translation is one tap and one Enter away
  from a cloud one.
- **Known edge, not handled** (the user's choice: keyboard only). Squirrel
  receives no mouse events (F21). So Right Option held for a mouse click and
  released within 500 ms also counts as a tap, as Shift+click does for the
  Shift tap (§5.5). The notice shows it, and another tap switches back.
- With no cloud slot configured, the switch stays on local, and the notice
  says `云端未配置`.
- Nothing is committed and nothing is cleared (§6.3).

**One choice for the whole process.** The active slot is not a Rime option.
Options live in each session's `Context` (F14, F24), so a switch made in one
app would not reach another. The network is the machine's, so the choice is
too: it is module-level state in `ime_translate_shared`, which every session
shares (the test in §6.1: it must *not* differ between input boxes).

**Remembered.** The active slot is written to
`~/Library/Rime/ime_translate.active`, one word, `local` or `cloud`, on every
switch. It is read with the config, once per Lua state, so a redeploy or a
restart keeps it (F28; the user's decision, 2026-09-22). A missing or
unreadable file, or `cloud` with no cloud slot, starts on local. A failed write
still switches, for this Lua state; the log says so.

**What the user sees.**
- **On a switch**, Squirrel's own status message, where the Chinese/English
  notice appears: `本地翻译`, `云端翻译` or `云端未配置`. The schema declares
  three switches for it whose off state has an empty label, with an `abbrev`
  equal to their states so the whole label shows, and the processor turns one
  on and off. With an empty first label a switch is left out of the
  switcher menu, and Squirrel shows a message only for a non-empty label (F29).
- **On every translation**, the prompt says where it came from: `  ☁ …` for a
  translation from a non-loopback `base_url`, and `  ☁ ✗ …` for its errors; a
  loopback one keeps `  -> …` (§6.4). It is decided by the URL, not the slot
  name, so a "local" slot pointed at a cloud still shows ☁. This is the
  explicit cloud marker §7.2 asks for.

**Measured by the user (2026-09-22, [smoke-report-003.md](../smoke-report-003.md)
R1, R2), as derived from F29: the switch notice is not seen with candidates on
screen.** Squirrel drops a status message whenever the panel has candidates to
draw.
- **The notice shows** with nothing typed, and with a draft whose segments are
  all selected.
- **With unselected pinyin it does not.** The pinyin stays, but a highlight
  moved by hand returns to the first candidate: the option change refreshes
  the open segment (F20).
- The `☁` on the next translation still says which backend answered.

**Unchanged.** One commit exit, never eat text, send is always manual, keys
only in the Keychain (§7.3): each slot names its own Keychain account, and
both keys are read once per Lua state.

## 6. Session state and invalidation

### 6.1 Where state lives

librime's `Context` properties (`ctx:set_property(k, v)` /
`ctx:get_property(k)`). Context is per session; the processor reaches it
through `env.engine.context`, so switching application, input box
or schema each stay independent. **Do not use `require` module singletons** —
librime-lua gives every registered Lua component one shared Lua state at init,
so module-level state is shared across all input sessions.

| key | meaning |
|---|---|
| `ime_translate.phase` | `idle` / `result` / `error` |
| `ime_translate.text` | the translation (result phase) |
| `ime_translate.code` | error code (error phase) |
| `ime_translate.draft` | **snapshot of the draft when translation was triggered; doubles as the version identifier** |
| `ime_translate.cloud` | `1` when the result or error came from a non-loopback `base_url` (feature 003) |
| `ime_translate.fallback` | `1` when the cloud slot failed and the result is the local slot's (feature 005) |

No separate version counter: the draft text is its own version.
**Current draft ≠ snapshot ⇒ the user edited ⇒ the translation is void.**

> **Why the draft can be its own version (D1, 2026-09-21).** The draft is read
> through `ctx:get_commit_text()`, which includes the highlighted candidate of
> every open segment ([upstream.md §15.2](upstream.md) F5). The first version of
> this design displayed the translation as a candidate in that same menu, so the
> display changed the "version" it was checked against ([risks.md §12](risks.md)
> R10); spike S11 measured that failure with the draft fully confirmed and with
> the last segment open. The translation is now shown through the last
> segment's `prompt` (§6.4), which `get_commit_text()` never reads (F9, measured
> in S11), so the snapshot is a clean version: in S11 row 5a one letter typed
> after the prompt showed made the next Enter re-translate the edited draft.
> With the last segment open, the draft includes its highlighted candidate —
> Enter translates exactly what `Shift+Enter` would commit.

Config and the API key may still be cached at module level — they are
process-wide read-only data, unrelated to any session. So is the active backend
slot (feature 003, §5.6): it changes, but only by the switch key, and it must
be the same in every input box, because the network it answers to is the
machine's. So is the translation cache (feature 005, [backend.md §8.3](backend.md)):
the same draft sent to the same slot has the same translation in any input
box. The test: *would this
value need to differ because the user moved to another input box?* If yes, it
must live in Context.

### 6.2 Invalidation is checked in two places

Keys are not the only way to edit, so `decide` alone will miss cases.

1. **In decide**: anything other than Enter / Shift+Enter / Esc is
   `invalidate_and_pass` — clear the display first, then pass through. Rather
   than enumerating "which keys change the draft", one catch-all rule covers
   continued typing, backspace, cursor movement and candidate changes at once.
2. **At the top of every processor event**: compare the current draft against
   the snapshot; on mismatch clear the phase and the prompt. Catches whatever
   leaked — above all a mouse click on one of Rime's own candidates, which
   produces no key event. A translation is committed only by an Enter, and
   every Enter passes this check first, so **a stale translation is never
   committed**.

The first version had a third check, in the translator, for the mouse case. It
went with the translator (D1): as written it always reported stale, and it
could not see a click on the translation candidate at all
([upstream.md §15.3](upstream.md)).

**Residual:** after a mouse edit the old prompt can stay on screen until the
next key, if the edit did not rebuild the last segment. Paging the candidate
window does exactly that ([upstream.md §15.2](upstream.md) F17; Task 10 smoke
row 21, observed by the agent). The display can be stale
for that moment; the commit cannot, and an Esc aimed at the stale prompt keeps
the draft (§5.2).

**The opposite case, observed by the agent (Task 10 smoke row 22; the user
accepted agent observation for that task).** A click on the
*highlighted* candidate confirms the segment and opens an empty one after it:
the prompt vanishes while the draft stays the same, so check 2 has nothing to
see. Enter in `result` therefore commits only while the translation is the
prompt on the last segment; otherwise it shows it again, with no backend call,
and the next Enter commits (the user's decision). **Enter commits only what is
on screen.** In `error` the same click removes the `✗` reason; Enter then
translates again (feature 005), so nothing unseen is committed (a derivation
from the same mechanism).

### 6.3 Never eat text

On every path, before `ctx:clear()` a `commit_text()` must already have
committed either the Chinese draft or the English translation. The draft never
vanishes.

That holds only for the whole draft. `ctx:clear()` removes the whole input, but
with the caret inside it `get_commit_text()` holds only the part before the
caret — so the processor acts on the draft only with the caret at the end
(§5.2, [upstream.md §15.2](upstream.md) F15).

This is stronger than "on failure the candidate still holds the Chinese
original" — that phrasing depends on the engine committing that candidate, and
the engine's default Return behavior is exactly what does not guarantee it.

### 6.4 Display: the last segment's prompt (D1)

The processor writes the display into `ctx.composition:back().prompt`; no
translator or filter draws anything.

| Phase | `prompt` |
|---|---|
| `result` | `  -> ` followed by the translation; `  ☁ ` instead when it came from a non-loopback `base_url` (feature 003, §5.6); `  ☁✗ -> ` when the cloud slot failed and the local slot answered (feature 005) |
| `error` | two spaces followed by `✗ reason` ([backend.md §8.1](backend.md)); `  ☁ ✗ reason` from a non-loopback one |
| `idle` | empty |

- librime inserts the last segment's prompt into the preedit at the caret, and
  `get_commit_text()` never reads it ([upstream.md §15.2](upstream.md) F9). S11
  measured both states: `今天有點累  -> FAKE ENGLISH` with no candidate window
  when every segment was confirmed; the same prompt after the open pinyin
  segment, with Rime's own window still showing its candidates, when the last
  segment was open.
- The prompt belongs to the segment, so whatever rebuilds the segment removes
  it — typing a letter did (S11 row 5a). The processor does not rely on that: it
  clears the prompt itself on every path out of `result` and `error` (Esc, the
  catch-all, check 2), and after a commit `ctx:clear()` removes the segment.
- The processor does not call `refresh_non_confirmed_composition()` after
  writing it. The measured path wrote the prompt and returned kAccepted, nothing
  more; whether a refresh keeps the prompt is not measured.
- **Observed by the agent in Task 10's smoke checks** (`../smoke-report.md`;
  accepted by the user as that task's evidence): the
  result-phase Esc drops the prompt and keeps the draft (row 10); clicks on a
  candidate while the prompt shows (rows 22-23, and §6.2 above); a translation
  with a newline shows on two lines and commits as is (row 14). The prompt with
  the caret inside the input does not arise: Enter first moves the caret to the
  end (§5.2, rows 18-19).
- **Not measured:** how a long English prompt renders in each application
  (Task 11's matrix).
