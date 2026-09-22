# Implementation plan — feature 004, the Right Option tap

> **For agentic workers:** load the `plan-execution` skill and work one task at
> a time. Run `./scripts/progress.sh` as `PROGRESS_FEATURE=004 …`.

**Goal.** A lone tap of Right Option switches the translation backend, in every
application, with nothing typed. `Ctrl+Shift+B` is removed.

**Architecture.**
- **The tap module.** `shift_tap.observe` takes a tap descriptor: the keysyms
  that count, and the modifier bits that make a chord. `shift_tap.SHIFT` is the
  default, so 002's callers are unchanged. `shift_tap.RIGHT_OPTION` is
  `XK_Alt_R`. Its chord bits are Shift, Control and Command, since Squirrel's
  press carries the key's own Alt bit (F21, F30).
- **The processor** watches both taps on every key. It keeps the Option
  state in its own Context property, and on a Right Option tap it runs 003's
  switch: void, switch, notice.
- **`decide`** loses the `switch_backend` action, so `Ctrl+Shift+B` is native
  again.

**Design.** [design §5.6](../../../design/architecture.md), §5.2's row, and
upstream F30. The decision: [decisions.md](../../../design/decisions.md),
"Feature 004 designed".

## Global constraints

The same as feature 003's ([003 plan](../../003-backend-switch/plan/README.md)):
- English in every file, with Chinese only as data.
- Lua 5.4, with no dependencies.
- `commit_text` appears only in the processor.
- Session state lives in Context.
- The switch never eats text.

## Tasks

| # | Task | Depends on | Files |
|---|---|---|---|
| 1 | The Right Option tap switches; `Ctrl+Shift+B` goes | — | `shift_tap.lua`, `session.lua`, `decide.lua`, `ime_translate_processor.lua`, and their tests |
| 2 | Schema text, README, template; real-machine smoke (manual) | 1 | `luna_pinyin_translate.schema.yaml`, `README.md`, `rime/ime_translate.yaml`, `docs/smoke-report-004.md` |
