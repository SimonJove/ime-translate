# Upstream behaviour

Part of the design set — start at [overview.md](overview.md).

## 15. Upstream behaviour the design depends on

What librime, librime-lua and Squirrel actually do at the points Plan A′ leans
on. [evidence.md §14](evidence.md) is about the translation backends; this is
about the host the IME runs inside.

### 15.1 How this was checked, and what it is not

Read from upstream source on 2026-09-20, in a design review held before Task 1
started:

| Repository | Revision read |
|---|---|
| `rime/librime` | master; tags 1.8.5, 1.11.2, 1.13.1 and 1.14.0 for F6 only |
| `hchunhui/librime-lua` | master |
| `rime/squirrel` | master |
| `rime/rime-prelude`, `rime/rime-luna-pinyin` | master |
| `rime/librime` | tag 1.16.0 — the installed version — for F13–F20, F23, F26 and F27, read 2026-09-21 and -22 |
| `rime/squirrel` | tag 1.1.2 — the installed version — for F21 and F24, read 2026-09-21 |
| `hchunhui/librime-lua` | master, for F22 and F25, read 2026-09-21; the installed build checked by binary inspection only |

**None of it was measured on this machine.** Squirrel was not installed yet, and
the build Homebrew installs may not match master. [risks.md §12](risks.md) keeps
vendor claims, estimates and this project's own measurements apart; the same
split applies here:

- §15.2 is **source readings** — what the code says.
- §15.3 and §15.4 are **derivations** — what follows from those readings for
  our design.
- The **measurements** are S2 and S11–S14 in [testing.md §10.2](testing.md).

The spike report settles every row below. Where it disagrees, the report wins
and this section is corrected in Task 12.

### 15.2 Source readings

Files and symbols are named rather than line numbers, which drift.

| # | Where | What the code does | Bears on |
|---|---|---|---|
| F1 | librime `gear/editor.cc` `FluidEditor::FluidEditor`; `engine.cc` `ConcreteEngine::OnSelect` | `FluidEditor` constructs `Editor(ticket, false)`, i.e. `_auto_commit` off. When a selection reaches the end of the input, `OnSelect` then calls `composition().Forward()` instead of `ctx->Commit()`. Native bindings: Return → `CommitComposition`, Shift+Return → `CommitScriptText`, Control+Return → `CommitRawInput`, BackSpace → `BackToPreviousInput`; other printable characters → `AddToInput` | S1 — expected to pass. This is what the stock `luna_pinyin_fluency` schema has always done |
| F2 | librime `gear/key_binder.cc` `select_schema` | A binding with `select: <schema_id>` applies that schema; `select: .next` cycles | S5 — expected to pass |
| F3 | librime `config/legacy_preset_config_plugin.cc` | With `key_binder/import_preset` present, a sibling `bindings` list is **appended** to the preset's list (`bindings/+`). Without `import_preset` a schema has only its own bindings — no paging keys, no Tab, no emacs keys | Task 10's `key_binder` |
| F4 | librime `gear/punctuator.cc` `AutoCommitPunct`, `ConfirmUniquePunct`; rime-prelude `symbols.yaml`, `punctuation.yaml` | A punctuation definition that is a map with a `commit` key calls `Context::Commit()` **unconditionally** — `_auto_commit` is not consulted. A definition that is a plain string value goes through `ConfirmCurrentSelection()` → `OnSelect`, which under F1 only advances the composition. `luna_pinyin` sets `punctuator/import_preset: symbols`, whose `half_shape` defines `, . ? ; : ! ^` in the `{ commit: … }` form | S2 — **expected to fail** with the stock preset. §5.3 |
| F5 | librime `composition.cc` `Composition::GetCommitText` | For **every** segment, whatever its status, appends `seg.GetSelectedCandidate()->text()` when the segment has a candidate, otherwise the raw input slice. So `ctx:get_commit_text()` is: confirmed text **+ the currently highlighted candidate of every open segment** + any unconverted input | §6.1 — the draft is not independent of the candidate menu |
| F6 | librime `engine.cc` `ConcreteEngine::TranslateSegments` | Every segment below `kGuess` is sent to every translator, and `segment.menu` is assigned only **after** all `Query` calls have returned. Tag 1.8.5 skips zero-length segments (`if (len == 0) continue`); 1.11.2, 1.13.1, 1.14.0 and master do not. So on current versions the trailing empty segment of a fully confirmed composition **is** translated, with input `""`; on old ones it never is | §6.2 — display in the fully confirmed state is version-dependent |
| F7 | librime-lua `src/lua_gears.h` `LuaTranslation` | The constructor calls `Next()`. A Lua translator therefore runs up to its first `yield` **inside** `Query` — per F6, before the segment it is filling has a menu | §6.2 check 3 |
| F8 | librime `context.cc` `ClearNonConfirmedComposition`, `RefreshNonConfirmedComposition` | Pops trailing segments below `kSelected`, pushes a fresh empty one, fires the update notifier so the engine recomposes. Confirmed segments are untouched | What `refresh_non_confirmed_composition()` can and cannot rebuild |
| F9 | librime `composition.cc` `Composition::GetPreedit`, `GetPrompt` | The last segment's `prompt` string is inserted into the preedit text at the caret. `GetCommitText` never reads `prompt` | R10 — a display channel that is not a candidate |
| F10 | librime `context.cc` `Context::Commit`, `Context::Clear`; `gear/memory.cc` `Memory::OnCommit` | `Commit()` fires `commit_notifier`, then `Clear()`. `Clear()` resets input, caret and composition and fires only the update notifier; **properties are untouched**. User-dictionary learning hangs off `commit_notifier` | Task 9's explicit `session.clear` is right. R13 — the `commit_text()` + `ctx:clear()` path never teaches the user dictionary |
| F11 | Squirrel `sources/SquirrelInputController.swift` `commitComposition(_:)`, `deactivateServer(_:)` | `commitComposition` commits `get_input` — the **raw key string** — then clears the composition. `deactivateServer` calls it | R11 |
| F12 | Squirrel `sources/MacOSKeyCodes.swift` `osxModifiersToRime` | With Caps Lock on, `kLockMask` is set in the modifier of every key event | R15 — `decide` masks the modifier to Shift / Control / Alt / Super (Task 8) |
| F13 | librime `gear/simplifier.cc` `Simplifier::Simplifier`, `Simplifier::Apply`; `candidate.h` `ShadowCandidate::comment`; `engine.cc` `ConcreteEngine::TranslateSegments` | With no `simplifier/option_name`, the filter reads the option `simplification`. When that option is off, `Apply` returns the translation untouched. When it is on, converted candidates become `ShadowCandidate`s; with `tips` unset and `inherit_comment` defaulting to true, the original candidate's comment carries through. Filters are attached to the segment's menu, so the candidate F5 reads is the filtered one | D5 — the draft's script is whatever the simplifier produced. §8.1's `✗` comment survives a Lua filter placed before `simplifier` |
| F14 | librime `engine.cc` `ConcreteEngine::ConcreteEngine`, `ApplySchema`, `InitializeOptions`; `switcher.cc` `Switcher::RestoreSavedOptions`; `context.cc` `Context::ClearTransientOptions`; `gear/switch_translator.cc` `SwitchTranslation::LoadSwitches`; `gear/key_binder.cc` `toggle_option` | Options live in the `Context`, not the schema. A new session restores the `switcher/save_options` from `user.yaml` `var/option/*` once, then applies `reset` for the switches the schema declares. A schema switch clears only `_`-prefixed options and re-applies `reset`, so an option the new schema does not declare **carries over** from the previous one. An option is written to `user.yaml` only when toggled from the switcher menu, which lists only the current schema's declared switches; a `key_binder` `toggle` is never saved | D5 |
| F15 | librime `engine.cc` `ConcreteEngine::Compose`; `segmentation.cc` `Segmentation::Reset`; `composition.cc` `Composition::GetCommitText`, `GetPreedit`; `gear/navigator.cc` `Navigator::Rewind`; `gear/editor.cc` `CommitComposition`, `CommitScriptText` | `Compose` resets the composition to `input().substr(0, caret_pos())`; only when the caret sits at the confirmed position (always at the start) does it reset to the whole input. So with the caret inside unconverted input `GetCommitText` stops at the caret, while `GetPreedit` also shows the input after it. Left moves the caret into unconverted input. Native Return confirms the highlighted candidate, which moves the caret to the end without committing; `CommitScriptText` is truncated like `GetCommitText` and then clears. librime-lua `types.cc` `ContextReg` maps `ctx.caret_pos = …` to `Context::set_caret_pos`, which clamps to the input length and fires the update notifier; `OnContextUpdate` runs `Compose` at once — the setter End and `RimeSetCaretPos` use. Read at tag 1.16.0 (librime-lua master) by the Task 9 review, rounds 1 and 2 | §5.2's caret rule; §6.3 |
| F16 | librime `switcher.cc` `Switcher::SetActiveSchema`, `Switcher::CreateSchema`; `fix_schema_list_order` | Selecting a schema saves `var/previously_selected_schema` to `user.yaml`, and every new session starts in it. `fix_schema_list_order` would instead start in the first entry of `schema_list` (`luna_pinyin` here, not `luna_pinyin_simp`). Read at tag 1.16.0 by the Task 10 review | architecture.md §5.1 as corrected; D6 |
| F17 | Squirrel `SquirrelPanel.sendEvent` (`.scrollWheel`, and `.leftMouseUp` on a page arrow), `SquirrelInputController.page(up:)`; librime `rime_api` `RimeChangePage`, `Context::Highlight` | Scrolling or clicking a page arrow on the candidate window pages it through the API, with no key event: the highlight changes, so the draft can change, and nothing reaches the processor until the next key. Read by the Task 10 review, round 3 | §6.2's check 2 and its residual; smoke row 21 |
| F18 | librime `gear/ascii_composer.cc` `AsciiComposer::LoadConfig`, `load_bindings`, `ProcessKeyEvent`, `ToggleAsciiModeWithKey`, `ProcessCapsLock` | `switch_key` is read from the schema; only if the schema has none is `default.yaml`'s used, `good_old_caps_lock` included, so a schema-level map replaces the whole default one. A `noop` style stores no binding, and a Shift release with no binding toggles nothing. A Shift released with no key seen in between (within 500 ms) toggles `ascii_mode`, and any other key it sees resets that. With `good_old_caps_lock` and Lock set, `ProcessCapsLock` can reject a key to the application. Read at tag 1.16.0 by the Task 10 review, rounds 3 and 4 | architecture.md §5.2 (Shift switches nothing); schema change 8 |
| F19 | librime `gear/ascii_segmentor.cc` `AsciiSegmentor::Proceed`; `gear/fallback_segmentor.cc` `FallbackSegmentor::Proceed`; `gear/ascii_composer.cc` `ProcessKeyEvent`, its tail | With `ascii_mode` on, `ascii_segmentor` makes the rest of the input one segment tagged `raw` and ends segmentation. Outside it, `fallback_segmentor` also tags the characters no other segmentor claimed `raw`, one at a time. With `ascii_mode` on and a composition open, `ascii_composer` pushes every key from 0x20 to 0x7F into the input — except Shift+space and chords with Control, Alt or Super. With no composition it rejects the key to the application. Read at tag 1.16.0 for feature 002 | §5.5: in English mode nothing counts as unselected, so Enter translates at once (the processor, feature 002 Task 7). `ime_translate_raw`, which used this, was dropped (D8) |
| F20 | librime `context.cc` `Context::ConfirmCurrentSelection`, `set_option`, `RefreshNonConfirmedComposition`; `engine.cc` `ConcreteEngine::OnSelect`, `OnOptionUpdate`, `TranslateSegments` | `ConfirmCurrentSelection` marks the last segment selected and fires the select notifier; on an empty segment with no candidate it returns false without firing. `OnSelect` never commits unless `_auto_commit` is set (it is not under `fluid_editor`): at the end of the input it confirms the segment and opens an empty one after it. `set_option` fires `OnOptionUpdate`, which, while composing, clears and recomposes the non-confirmed composition. `TranslateSegments` skips every segment already selected or confirmed. Read at tag 1.16.0 for feature 002 | §5.5: lock, then switch |
| F21 | Squirrel `sources/SquirrelInputController.swift` `handle(_:client:)`, the `.flagsChanged` case; `recognizedEvents` | Each change of the Shift, Control, Option or Command flag becomes one Rime key event, carrying the keysym of the key that caused it. A second Shift pressed while the other is held, or the first of two released, changes no flag and sends nothing (narrowed by 002 Task 1's review). A press carries the mask after the change, so Shift's press has the Shift bit. A release carries that mask without the Shift bit, plus `kReleaseMask`. Releases are sent before presses. A keyDown with Command is never sent. The controller receives only `.keyDown` and `.flagsChanged`, so a mouse click reaches Rime as nothing. Read at tag 1.1.2 (master is the same here) for feature 002 | `shift_tap`; §5.5 Shift+click |
| F22 | librime-lua `src/types.cc` `RimeApiReg`, `get_time_ms` (commit 701cb4e, #409, 2025-06-28) | `rime_api.get_time_ms()` returns `std::chrono::steady_clock` milliseconds. The installed `librime-lua.dylib` contains the name `get_time_ms` — binary inspection, not a call | §5.5: the 500 ms window |
| F23 | librime `gear/editor.cc` `FluidEditor::FluidEditor`, `Editor::BackToPreviousInput`; `context.cc` `ReopenPreviousSegment`, `ReopenPreviousSelection`, `PopInput`; `segmentation.cc` `Segment::Close`, `Segment::Reopen`, `Segmentation::Trim`, `Forward`, `AddSegment`, `Reset`; `engine.cc` `Compose`, `CalculateSegmentation`; `composition.cc` `GetCommitText` | `fluid_editor` is an `Editor` with `_auto_commit` false. BackSpace runs `ReopenPreviousSegment`, else `ReopenPreviousSelection`, else `PopInput`. `ReopenPreviousSegment` drops a trailing empty segment and reopens the confirmed one before it; with the caret at its end it goes back to `kGuess` with its candidates kept, and nothing is deleted. `ReopenPreviousSelection` stops at the first confirmed segment. `PopInput` changes the input, and `Reset` drops every segment that reached past the change, so the rest is segmented again under the current options. `Segment::Close` cuts a segment short when the selected candidate is shorter, and the remainder is segmented again. `AddSegment` replaces a shorter segment at the same start, an empty one included, status and all. `GetCommitText` takes a segment with no candidate as its raw input. Read at tag 1.16.0 by the feature 002 design review | §5.5 edges; R17 |
| F24 | Squirrel `SquirrelInputController.swift` `init`, `createSession`, `updateAppOptions`, `handle(_:client:)`; `SquirrelApplicationDelegate.swift` `notificationHandler`; `data/squirrel.yaml` `app_options` | Each input controller creates its own Rime session, and options such as `ascii_mode` live in it. `app_options` are applied when the session is created, and again whenever the controller's client app changes. The stock file, as built here, starts Terminal, iTerm2, Hyper, VS Code, Xcode, Spotlight and a dozen others with `ascii_mode: true`. Every option change is shown as a status message with the switch's state label, unless notifications are off. Read at tag 1.1.2 by the feature 002 design review | §5.5: the mode is per session |
| F25 | librime-lua `src/types.cc` `ContextReg` (methods and setters), `SegmentReg`, `CandidateReg::make`; `src/lua_gears.cc` `raw_init`, `LuaTranslator::Query`, `LuaTranslation::Next`; `src/lib/lua.cc` (`yield`) | Context has `confirm_current_selection`, `get_option`, `set_option`, and a `caret_pos` setter. Segment has `start` and `_end` and `has_tag`. `Candidate(type, start, end, text, comment)` makes a `SimpleCandidate`. `lua_translator@NAME` is the global `NAME` (a leading `*` requires a module instead). `Query` runs it with `(input, segment, env)` in a coroutine, `input` being the segment's text, and each global `yield` hands one candidate back. An error is logged and ends the translation. Read on master by the feature 002 design review | Tasks 3–5 |
| F26 | librime `gear/ascii_composer.cc` `ProcessCapsLock`, `SwitchAsciiMode`; Squirrel `MacOSKeyCodes.swift` `osxKeycodeToRime`, `handle(_:client:)` `.keyDown` (tag 1.1.2) | With a `Caps_Lock` style other than `noop`, `ProcessCapsLock` runs first on every key. A Caps Lock press with `good_old_caps_lock`, while `ascii_mode` is on and was not turned on by Caps Lock, is rejected to the application: no switch, and nothing cleared. Otherwise it switches the mode in the given style, and `clear` clears the composition. Then every key carrying the Lock bit is rejected to the application under `good_old_caps_lock`. With `noop` none of this runs. Squirrel sends a letter typed with Caps Lock on as its uppercase keysym. Read at tag 1.16.0 by the feature 002 design review | R16; D7 |
| F27 | librime `gear/editor.cc` `FluidEditor::FluidEditor`, `Editor::Confirm`, `CommitComposition`, `CommitRawInput`; librime-lua `src/types.cc` `CompositionReg`, `SegmentationReg`, `SegmentReg` (setters) | `fluid_editor` binds Space to `Confirm`, which is `ConfirmCurrentSelection() \|\| Commit()`. With nothing left to select, Space commits the whole draft to the application, untranslated. Return is bound to `CommitComposition`, and Control+Return to `CommitRawInput`. In librime-lua the Composition object has only `empty`, `back`, `pop_back`, `push_back`, `has_finished_composition`, `get_prompt`, `spans` and `toSegmentation`. `get_confirmed_position`, `add_segment` and `forward` are reached through `toSegmentation()`; calling them on the composition fails with "attempt to call a nil value", which the 2026-09-22 spike hit. `Segment(start, end)` makes a segment, and `status`, `_end`, `length` and `menu` have setters. In the spike an error raised inside a `lua_processor` reached no Rime log file; only a `pcall` inside the spike made it visible. Read at tag 1.16.0 and on librime-lua master by the feature 002 redesign | §5.5: the Enter way |
| F28 | librime-lua `src/modules.cc` `rime_lua_initialize` (as read by 002 Task 5's review); Squirrel `--reload` | Each time the Lua module initializes, a new Lua state is built and `rime.lua` runs again, and a redeploy re-initializes it. So a redeploy reloads every Lua module and, with it, `ime_translate.yaml` and the Keychain key, which `ime_translate_shared` reads once per Lua state. **Agent-observed, 2026-09-22:** with the config switched between `translate` and GLM, `Squirrel --reload` alone changed the backend both ways (`I'm a little tired today.` and then `A bit tired today.`), with no `--quit`. The Task 5 review had also read a pre-restart process writing the new processor's state after a `--reload` | `install.sh`'s notice; README, Configure; `ime_translate.yaml`'s header |

### 15.3 Derivation: the Enter loop under §6.1 and §6.2 as written

Derived from F5–F8, not observed. S11 is the measurement.

The design takes the draft, and the snapshot that versions it, from
`get_commit_text()` (§6.1), and displays the translation as a candidate in the
last segment's menu (§6.2). F5 says those two interfere: a displayed candidate
is part of the commit text.

**State A — the whole draft is confirmed** (space-confirmed, or ending in
punctuation). The composition ends in an empty segment.

1. Enter: snapshot = the Chinese draft. `refresh_non_confirmed_composition()`
   rebuilds the empty segment.
2. On librime 1.8.5 the empty segment is never translated (F6): no candidate, no
   window, nothing to hang an error comment on either.
3. On 1.11.2 and later the translator runs. Its staleness check passes — the
   segment has no menu yet, so the commit text is still the Chinese — and the
   English candidate becomes the segment's only, highlighted candidate.
4. Second Enter: the processor's check now reads Chinese **+ English** (F5) ≠
   snapshot → stale → state cleared → `decide` sees `idle` → **translates
   again**, this time sending Chinese + English. The translation is never
   committed; the two states alternate.

**State B — the last segment is still open** (candidates showing).

1. Enter: snapshot = confirmed Chinese + the highlighted Chinese candidate.
2. The refresh rebuilds the last segment. Inside `Query` it has no menu yet (F6,
   F7), so the translator's check reads confirmed Chinese + **raw pinyin** ≠
   snapshot → stale → nothing is yielded. The user sees a freeze and then no
   translation.
3. Second Enter: the menu is back, the commit text equals the snapshot again,
   phase is still `result` → the processor **commits an English sentence the
   user was never shown**.

Two further consequences of displaying through a candidate, independent of the
above:

- A mouse click on the translation candidate selects it like any other: the
  English becomes a confirmed segment inside the Chinese draft. §6.2's third
  check stops the candidate being *regenerated*; it cannot undo a selection that
  has already happened.
- A Lua `Candidate` has quality 0 by default. Against a `script_translator`
  candidate with the same span it is not guaranteed to sort first.

None of this is reachable from the headless tests: the fake context in Task 7
returns a fixed commit text.

### 15.4 Derivation: the script of the draft in the translation schema

Derived from F5, F13 and F14, not observed. Read against Task 10's plan as it
stood when D5 was opened: `simplifier` in the translation schema's filters, no
`simplification` switch declared. `luna_pinyin`'s dictionary is Traditional; only the
simplifier turns it into Simplified.

- **Entered with `Ctrl+Shift+T` from `luna_pinyin`** — the option carries over
  from `luna_pinyin`. On the development machine that schema now resets it to on
  (a local `luna_pinyin.custom.yaml`, 2026-09-21), so the draft is Simplified.
- **A session that starts in the translation schema** (Squirrel opens a new
  session in the previously selected schema) — the value saved in `user.yaml`
  if the user ever toggled it from `luna_pinyin`'s switcher menu, otherwise off:
  **Traditional**. The `reset` in the local `luna_pinyin.custom.yaml` writes
  nothing to `user.yaml`, so it does not help here.
- **Inside the translation schema** the switcher menu does not offer the option
  at all; `Ctrl+Shift+4` from the default preset's `key_binder` flips it for
  the rest of the session, unsaved.

So the same keystrokes commit either script, depending on how the session got
there. The draft is read from candidates (F5, F13), so three things follow the
option: the Chinese committed by `Shift+Enter`, the Chinese committed on the
error fallback, and the text sent to the backend. The default backend's source
language is `zh` ([backend.md §7.5](backend.md)), which Translation.framework
lists apart from `zh-TW` ([evidence.md §14.2](evidence.md)). What Traditional
input does to `zh`→`en` quality is **unverified** in both directions — it may
be harmless.

Settled by: entering the schema both ways on the real machine and seeing which
script `Shift+Enter` commits; and sending the same sentence to the backend in
Traditional and in Simplified.

**Under D5's outcome** (the switch declared without `reset`,
[decisions.md §13](decisions.md)) the first two cases are unchanged — with no
`reset`, `InitializeOptions` never touches the option. The third changes: the
switcher menu now lists it, and toggling it there writes
`var/option/simplification` to `user.yaml`, because `simplification` is in
`default.yaml`'s `switcher/save_options`. Once saved, a session that starts in
the translation schema restores the user's choice instead of falling back to
Traditional. Toggling from `luna_pinyin`'s menu saves the same key.

**Under the Task 10 revision (D5 amended, 2026-09-21)** the schema pairs with
`luna_pinyin_simp` and reads its option `zh_simp`. `zh_simp` is not in
`default.yaml`'s `switcher/save_options` (source reading of the installed
`default.yaml`), so it is never saved or restored. Declared without `reset`, it
would be off, and the draft Traditional, in every session that starts in the
translation schema. It is therefore declared with `reset: 1`, as in
`luna_pinyin_simp`. The draft is Simplified whenever the schema loads, and a
toggle lasts for the session. This is a derivation from F14; Task 10's smoke row
16 measures it.

### 15.5 Derivation: feature 002 under the source

Derived from F18–F26 by the feature 002 design review. None of it is measured;
each point names the Task 6 row that settles it.

**The tap, with a pinyin segment open (§5.5, the spike's case).**
1. The release confirms the segment: F20's `OnSelect` marks it confirmed and
   opens an empty segment after it.
2. `set_option` recomposes what is not confirmed: only that empty segment.
3. The first English character replaces the empty segment with a `raw` one
   (F23's `AddSegment`), and the raw candidate answers.

It holds after a selection too, and with two taps in a row. There the second
confirm meets the empty segment and returns false; that segment is left marked
selected, so `set_option` recomposes nothing. The next character replaces it
all the same. Task 6 rows 1–6 and 14.

**A highlighted candidate shorter than its segment.** `Segment::Close` locks
only what the candidate covers. The rest is segmented again in the new mode:
pinyin after the highlight becomes English letters. Task 6 row 28.

**BackSpace into a locked segment of the other mode (R17).**
1. The first BackSpace after the lock deletes nothing. It reopens the segment,
   candidates kept, so the screen does not change.
2. The next one deletes a character, and `Reset` segments what is left of that
   segment again, under the current mode. In Chinese mode `readme` minus one
   letter is read as pinyin. In English mode a Chinese segment turns back into
   its pinyin letters.

Nothing is lost: the input is intact, and it commits as shown. A tap at step 1
locks the reopened segment again, so switching to its mode before editing it
works. Task 6 rows 23 and 24.

**Caps Lock after a tap (R16).**
1. With a draft in English mode reached by a Shift tap, the Caps Lock press is
   rejected to the application (F26). The draft stays.
2. The next letter carries the Lock bit and is rejected to the application
   too. The spike's R15 measurement saw a rejected key replace the marked
   text, so the letter replaces the whole draft.

In Chinese mode, `Caps_Lock: clear` already clears the draft on the press (001
smoke row 26). Both paths break "never eat text", and 002 makes the first one
likely: Caps Lock is how many people type capitals. `Caps_Lock: noop` would
close both. Letters would then reach the draft as capitals: in English mode
through `ascii_composer`, in Chinese mode through the recognizer's `uppercase`
pattern. That is decision D7. Task 6 row 25.

**The mode is per session (F24).** "The mode after a commit stays as it was"
holds inside one Rime session. Another document or app has its own session,
and it starts in the schema's reset mode, which is Chinese. Apps listed with
`ascii_mode: true` start in English, and return to English whenever the client
app changes. In 001 a Shift tap did nothing in those apps, and Caps Lock is
rejected there while `ascii_mode` is on. Only the switcher menu or
`Control+Shift+2` reached Chinese. Task 6 row 26.

**The other switch.** The preset `key_binder` binds `Control+Shift+2` (and
`Control+Shift+at`) to toggle `ascii_mode`: it is in this schema's build. That
toggle calls `set_option` directly, so with a draft open the open segment is
read again in the new mode, the spike's unlocked case (F20). Nothing is lost.
The Shift tap is the switch that locks. Task 6 row 27.

### 15.6 What the machine confirmed (written back by 001 Task 12)

Each F-row against what was later seen on this machine: Squirrel 1.1.2 and
librime 1.16.0 throughout. "Agent" means the agent drove and observed it;
"user" means a person saw it.

| F-row | Seen | By |
|---|---|---|
| F1 `fluid_editor` does not auto-commit | S1 pass | spike (agent, accepted) |
| F2 `select:` switches schemas | S5 pass; 001 smoke row 16 | spike, agent |
| F4 `{ commit: … }` punctuation commits | S2 fail, exactly as read | spike |
| F5–F7, F9 the display candidate vs `segment.prompt` | S11 went step for step as §15.3 derived; nothing in §15.3 needed correcting | spike |
| F11 focus loss commits the raw keys | S12; 001 Task 11 matrix (Chrome commits the spaced preedit) | spike, agent |
| F12 Caps Lock sets the Lock bit | R15 measured; the fix in `decide` | spike |
| F15 the caret truncates the composition | 001 smoke rows 18–19; 002 row 39; 001 Task 12 K7 | agent |
| F17 paging changes the draft with no key | 001 smoke row 21 | agent, accepted |
| F18 `ascii_composer` toggles on a lone Shift release | found in use: Shift+Enter switched the IME to English (2026-09-21) | user |
| F19–F20 English mode, the lock order | the 2026-09-21 spike (F12 standing in for the tap) | agent |
| F21 what Squirrel sends for Shift | 002 Task 6: the Shift rows, confirmed as a whole | user, overall |
| F22 `get_time_ms` | only the name, in the binary; the tap works either way | not measured |
| F23 BackSpace reopens a locked segment | 002 Task 6 row 41; 001 Task 12 K3 | agent |
| F24 per-session mode, `app_options` | 001 Task 11: Terminal starts in English | agent |
| F26 `ProcessCapsLock` | moot since D7 (`Caps_Lock: noop`); 002 row 43, confirmed as a whole | user, overall |
| F27 Space's native commit; the Composition API | the 2026-09-22 spike (`get_confirmed_position` needed `toSegmentation`); 002 rows 38, 40 and 47 | agent |

Nothing the machine showed contradicted a source reading. The one correction
came from a reading itself: §5.5's claim that the lock needs a candidate
(F20, D8).

