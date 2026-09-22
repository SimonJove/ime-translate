# Implementation plan — feature 002, mixed Chinese and English

> **For agentic workers:** load the `plan-execution` skill and work one task at
> a time. Steps use `- [ ]` checkboxes for tracking. Feature 001 is still open,
> so run every `./scripts/progress.sh` command for this one as
> `PROGRESS_FEATURE=002 ./scripts/progress.sh …`: `done` takes no `[id]`.

**Goal.** English goes into a Chinese draft as typed, and Enter translates the
whole mixed sentence, keeping the English words.
- **The main way (redesigned 2026-09-22).** As in the macOS Pinyin IME, type
  the letters and press Enter: unselected pinyin becomes the letters typed.
  Space with nothing unselected adds a space.
- **The supplement.** A lone Shift tap switches between Chinese and English.
  This is for English with digits or punctuation.

**Architecture.**
- The processor, first in the chain, owns Enter, Space and the Shift tap.
- **Enter with unselected pinyin.** The processor clears what is not
  confirmed, puts one bare segment over it, and confirms that segment. A
  segment with no candidate is confirmed as raw input (F20). It never switches
  the mode.
- **Space with nothing unselected.** The processor pushes a space and
  confirms it the same way.
- **The Shift tap.** A pure module tells a lone tap from Shift used as a
  modifier. On a tap with a draft open, the processor first locks the current
  segment by confirming its selection, then switches `ascii_mode`.
- **`decide` gains its rules:**
  - Enter on unselected pinyin locks it.
  - Enter on a draft with no Chinese commits it as is.
  - Space with nothing unselected is a literal space.
- **No translator is added.** D8 dropped the raw candidate. Caps Lock is
  `noop` in the schema (D7).

**Tech stack.** Lua 5.4, with zero external dependencies; librime-lua;
Squirrel.

**Design.** [design §5.5](../../../design/architecture.md), with the §4.1
component rows and the §5.2 key-table rows marked "feature 002". It resolves
through `./scripts/design-section.sh 5.5`. The evidence is the two spikes
recorded in [decisions.md](../../../design/decisions.md), "Feature 002
designed" and "Feature 002 redesigned".

**Before Task 1:** run `/design-review` on §5.5 and this plan. Every claim about
librime and Squirrel below is a source reading (upstream F18–F22) or a spike
observation, and none was measured with a physical Shift tap.

## Global constraints

- English in every file. Chinese appears only as data: in test string literals,
  in backticks or fenced blocks in `.md`, and in `rime/*.schema.yaml`.
- Lua 5.4, with no external dependencies. Tests are headless (`lua tests/…`).
  `scripts/run_tests.sh` runs them all.
- `engine:commit_text()` appears only in `ime_translate_processor.lua`.
  Session state lives only in Context properties.
- **Never eat text.** A tap confirms a selection and switches a mode. It
  commits nothing and clears nothing.
- **Send is always manual.** Nothing here presses Enter for the user.
- **Shift checks need a physical keyboard.** The agent's posted Shift events
  proved unreliable in feature 001, Task 10. A human watches Task 6's Shift
  rows.
- **The tap has ascii_composer's 500 ms window** (design §4.1; upstream F18).
  - The clock is librime-lua's `rime_api.get_time_ms()` (F22). That is a
    source reading; the installed `librime-lua.dylib` contains the name,
    which is binary inspection, not a call.
  - Where the function is missing, the processor passes no clock and any hold
    counts.
  - Squirrel sends no mouse events (F21). So a Shift+click released within
    500 ms is a tap, as it is for ascii_composer's own switching.

## Task overview

| # | Task | Deps | Produces | Check |
|---|---|---|---|---|
| 1 | [Shift tap recognition](task-01-shift-tap.md) | — | `shift_tap.observe(down, key, now)` | unit tests |
| 2 | [Enter on a draft with no Chinese](task-02-ascii-enter.md) | — | `decide.decide(key, phase, draft_empty, draft_ascii)` | unit tests |
| 3 | [The raw candidate](task-03-raw-translator.md) | — | `ime_translate_raw.lua` | unit tests + load test |
| 4 | [The processor locks and switches](task-04-processor.md) | 1, 2, 3 | the Shift-tap path in the processor; `session.shift_down` / `session.set_shift_down` | processor sequences |
| 7 | [Enter and Space — the Enter way](task-07-enter-space.md) | 4 | `decide.decide(…, unselected)`; `lock_literal`, `literal_space` | unit tests, processor sequences |
| 5 | [Schema and installer](task-05-schema.md) | 4, 7 | schema change 9 (`Caps_Lock: noop`); the raw translator dropped | install twice |
| 6 | [Real-machine smoke](task-06-smoke.md) (manual) | 5 | `docs/smoke-report-002.md` | every gate row passes |

**Task 7 came with the redesign of 2026-09-22 and runs before Task 5.** D7 and
D8 are closed (decisions.md, "Feature 002 redesigned"), and Tasks 5 and 6 were
revised before either started. Task 3's module is deleted by Task 5.

Tasks 1–3 are independent. **Feature 001's Task 10 must be in place first**,
which it is (commit `e08d206`). Its schema change 8 already makes
`ascii_composer`'s Shift keys `noop`, so nothing else toggles on Shift.

## File structure

| File | Responsibility |
|---|---|
| `rime/lua/ime_translate/shift_tap.lua` | **New.** Pure: `observe(down, key, now) -> down', tapped` |
| `rime/lua/ime_translate/decide.lua` | + the Enter rules (unselected pinyin; a draft with no Chinese) and the Space rule |
| `rime/lua/ime_translate/session.lua` | + the Shift state accessors |
| `rime/lua/ime_translate_raw.lua` | Built by Task 3, **deleted by Task 5** (D8) |
| `rime/lua/ime_translate_processor.lua` | + the tap path (lock, then switch) and the Enter way (`lock_literal`, `literal_space`) |
| `rime/luna_pinyin_translate.schema.yaml` | change 9: `Caps_Lock: noop` (D7) |
| `scripts/install.sh` | binds every component in `rime.lua` |
| `tests/test_shift_tap.lua` | **New** (`tests/test_raw.lua`: Task 3, deleted by Task 5) |
| `tests/test_decide.lua`, `tests/test_session.lua`, `tests/test_processor.lua`, `tests/test_glue_load.lua` | extended |
