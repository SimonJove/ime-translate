# Implementation plan — feature 003, switching the translation backend

> **For agentic workers:** load the `plan-execution` skill and work one task at
> a time. Steps use `- [ ]` checkboxes for tracking. If another feature is open,
> run every `./scripts/progress.sh` command for this one as
> `PROGRESS_FEATURE=003 ./scripts/progress.sh …`.

**Goal.** `Ctrl+Shift+B` switches translation between a local backend and a
cloud one: the cloud where the network is good, the local `translate` where it
is not.

**Architecture.**
- **Config.** `config.load` reads a second backend slot from `cloud_`-prefixed
  keys into `settings.cloud`. A cloud slot that fails a check is dropped; it is
  never replaced by the default backend.
- **The active slot.** `ime_translate_shared` holds it, process-wide: every
  session shares it, because the network is the machine's. It is read from
  `~/Library/Rime/ime_translate.active` with the config, and written there on
  every switch. `shared.current()` gives the active slot's settings and key.
- **The key.** `decide` returns `switch_backend` for `Ctrl+Shift+B` in every
  phase. The processor voids a translation on screen, switches, and turns a
  notice switch on and off: Squirrel shows its label (upstream F29).
- **The marker.** The session remembers whether a result or an error came from
  a non-loopback URL, and the prompt shows `  ☁ ` for it instead of `  -> `.

**Tech stack.** Lua 5.4, with zero external dependencies; librime-lua;
Squirrel.

**Design.** [design §5.6](../../../design/architecture.md), with the §4.1,
§5.2, §6.1 and §6.4 rows marked "feature 003"; the two slots in
[backend.md §9](../../../design/backend.md); the source readings in
[upstream.md](../../../design/upstream.md) F29. The decisions:
[decisions.md](../../../design/decisions.md), "Feature 003 designed".

**Before Task 1:** run `/design-review` on §5.6 and this plan. The notice rests
on F29, a source reading nobody has measured.

## Global constraints

- English in every file. Chinese appears only as data: in test string literals,
  in backticks or fenced blocks in `.md`, in `state.lua`, `config.lua` and
  `rime/*.schema.yaml`.
- Lua 5.4, with no external dependencies. Tests are headless (`lua tests/…`).
  `scripts/run_tests.sh` runs them all.
- `engine:commit_text()` appears only in `ime_translate_processor.lua`.
  Session state lives only in Context properties. The active slot is **not**
  session state (design §6.1): it lives in `ime_translate_shared`.
- **Never eat text.** The switch commits nothing and clears nothing; the draft
  stays.
- **Send is always manual.**
- **Keys only in the Keychain** (design §7.3). Each slot names its own account;
  warnings name keys, never values.
- A cloud slot never silently becomes `translate`.

## Tasks

| # | Task | Depends on | Files |
|---|---|---|---|
| 1 | The cloud slot in the config | — | `config.lua`, `tests/test_config.lua` |
| 2 | `Ctrl+Shift+B` in `decide` | — | `decide.lua`, `tests/test_decide.lua` |
| 3 | The active slot and the cloud marker | 1 | `ime_translate_shared.lua`, `session.lua`, `tests/test_shared.lua`, `tests/test_session.lua` |
| 4 | The processor switches and translates with the active slot | 2, 3 | `ime_translate_processor.lua`, `tests/test_processor.lua` |
| 5 | Schema notices, template, README | 4 | `luna_pinyin_translate.schema.yaml`, `rime/ime_translate.yaml`, `README.md` |
| 6 | Real-machine smoke (manual) | 5 | `docs/smoke-report-003.md` |
