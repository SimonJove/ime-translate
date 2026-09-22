# Implementation plan

> **For agentic workers:** load the `plan-execution` skill and work one task at
> a time. Steps use `- [ ]` checkboxes for tracking.

**Goal:** a macOS IME schema on Rime/Squirrel — type Chinese, press Enter to
translate, press Enter again to commit English. The IME owns the draft
throughout; the application only ever receives the final result.

**Architecture:** Plan A′ — a separate Rime schema `luna_pinyin_translate`
(alongside `luna_pinyin`, sharing its dictionaries), with `fluid_editor`
replacing `express_editor` so the composition does not auto-commit, making
Rime's own composition the Chinese draft buffer. One lua_processor owns
committing and calls `engine:commit_text()` directly, bypassing both candidate
selection and segment concatenation; the translator and filter only render.
Session state lives in librime `Context` properties, so it is per-session by
construction.

**Tech stack:** Lua 5.4 (zero external dependencies), librime-lua,
Squirrel, curl, macOS Keychain, launchd.

**Design:** [`docs/design/overview.md`](../../../design/overview.md). Every
`design §X.Y` citation below resolves through
`./scripts/design-section.sh X.Y`; executors read both.

## Task overview

12 tasks. **Task 1 is the global gate**, on three checks: S1, S3 and S11.
Either of S1/S3 falsified and Plan A′ does not exist — stop, return to design
([design §3.5](../../../design/architecture.md)), and do not quietly amend the
design to keep going. S11 falsified sends design §6.1–§6.2 back to design
review before any implementation continues; A′ itself may still stand
(decision D3, [design §13](../../../design/decisions.md)).

| # | Task | Deps | Produces | Gate |
|---|---|---|---|---|
| 1 | [Phase 0 spike](task-01-spike.md) | — | `docs/spike-report.md`; the S1–S14 verdicts and the constants later tasks need | **S1/S3/S11 life-or-death**; S11–S14 all in acceptance |
| 2 | [Scaffolding + JSON encoding](task-02-json-encode.md) | 1 | `json.escape` / `json.shq`, `scripts/run_tests.sh` | unit tests |
| 3 | [JSON decoding](task-03-json-decode.md) | 2 | `json.decode` | unit tests |
| 4 | [Phase constants and error strings](task-04-state.md) | 1 | `state.lua` | unit tests |
| 5 | [Config loading and validation](task-05-config.md) | 2 | `config.load` incl. tiered trust | unit tests |
| 6 | [Backend adapters](task-06-backend.md) | 2,3,4,5 | `backend.translate` × 3 adapters × 8 error codes | unit tests |
| 7 | [Session state and draft snapshot](task-07-session.md) | 4 | `session.lua` over Context properties | unit tests |
| 8 | [Pure-function key decisions](task-08-decide.md) | 4 | `decide.decide` | unit tests |
| 9 | [Rime glue layer](task-09-glue.md) | 5,6,7,8 | processor / shared (D1) | load smoke test + processor sequences |
| 10 | [Schema wiring + installer](task-10-wiring.md) | 9 | schema, `default.custom.yaml`, `install.sh`, LaunchAgent | **the real-machine smoke checks (Step 6)** |
| 11 | [README + matrix + blind eval](task-11-eval.md) | 10 | `docs/compat-matrix.md`, the default backend | blind-eval win rate |
| 12 | [Wrap-up and write-back](task-12-wrapup.md) | all | a daily-usable IME | full test run + clean reinstall |

**Parallelism**: Tasks 2–8 are pure headless Lua and, beyond the dependencies in
the table, do not interfere; 4 / 5 / 7 / 8 can run concurrently. From Task 9 on
everything is serial because it needs the real machine.

**Every task ends with "tests pass + one commit."** Steps inside a task are
2–5 minute actions; tick them off one `- [ ]` at a time.

## Where the status lives

**This directory holds no progress** — it is the immutable "how". The single
source of truth for execution state is
[`../progress.json`](../progress.json), read and written through
`scripts/progress.sh`:

```bash
./scripts/progress.sh status        # gate + all 12 tasks
./scripts/progress.sh next          # what is unblocked
./scripts/progress.sh show <n>      # deps, deliverables, acceptance, plan file
./scripts/progress.sh start <n>     # records the baseline commit
./scripts/progress.sh done <n> <hash>
./scripts/progress.sh gate pass|fail
```

Acceptance items live in progress.json and are printed by `show <n>`.
**No task is marked done with one unmet.**

The S1/S3/S11 gate is enforced by `.claude/hooks/gate-spike.sh`: while `gate`
is not `pass`, every write to `rime/` and `tests/` is refused. That is interception,
not a reminder.

## Global constraints

Every task's requirements implicitly include these.

- Platform: macOS 26+ / Apple Silicon / Apple Intelligence enabled. Measured
  environment **macOS 26**.
- Tests are `lua tests/test_<module>.lua` (`brew install lua` provides 5.4);
  **zero external Lua dependencies** (no busted, no cjson). Everything:
  `scripts/run_tests.sh`.
- **Never eat text**: before any `ctx:clear()`, an `engine:commit_text()` must
  already have committed either the Chinese draft or the English translation.
- **One commit exit**: `engine:commit_text()` may appear only in
  `ime_translate_processor.lua`. The translator and filter never commit.
- **No state in module singletons**: `phase` / `text` / `code` / `draft` all
  live in `Context` properties. librime-lua gives every registered component one
  shared Lua state. Config and the API key are process-wide read-only data and
  may be cached at module level.
- Config defaults (identical to [design §9](../../../design/backend.md)):
  `backend` = `libretranslate`; `base_url` = `http://127.0.0.1:8989`;
  `model` = `""` (decision D4: `translate` is the default, apfel cannot run on
  the development machine); `timeout_ms` = **`1500`** (local; **this
  value is the worst-case freeze after Enter**); `max_chars` = `2000`
  (**characters, not bytes**); `temperature` = `0.2` (**carried by the openai
  adapter only**); `max_tokens` = `1024` (anthropic only); the system prompt is
  design §7.4's text verbatim.
- **Tiered backend trust** ([design §7.2](../../../design/backend.md)): `allow_remote`
  defaults to `false` → non-loopback `base_url` refused; with `true`,
  non-loopback **must be `https://`**.
- **The API key goes in the macOS Keychain and never into `~/Library/Rime/`**
  ([design §7.3](../../../design/backend.md)). Config holds only `api_key_account`;
  logs and error strings never print the key. **Shell construction always uses
  `json.shq` (POSIX single quotes), never Lua's `string.format("%q", ...)`** —
  the latter is literal escaping whose double quotes still let `$()` and
  backticks expand.
- **`temperature` is adapter-private** ([design §7.7](../../../design/backend.md)) —
  it was removed on Claude Opus 5 / Sonnet 5 and sending it returns 400.
- **The schema hotkey is not this project's config**: `Ctrl+Shift+T` belongs to
  Rime's native `key_binder` `select:`; there is no toggle logic in Lua.
- The translation and `✗ `-prefixed error messages are shown in the last
  segment's `prompt`, after the draft in the preedit — never as a candidate
  (decision D1, [design §6.4](../../../design/architecture.md)).
- Personal use: unsigned, un-notarized, not shipped.
- Commit messages: `<type>: <summary>`, subject ≤ 72 chars.

## File structure

| File | Responsibility |
|---|---|
| `rime/lua/ime_translate/json.lua` | JSON encoding (`escape`), POSIX shell escaping (`shq`), JSON decoding (`decode`) |
| `rime/lua/ime_translate/state.lua` | Phase constants and error strings. **No state object** |
| `rime/lua/ime_translate/config.lua` | Flat YAML subset parsing, defaults, tiered-trust validation |
| `rime/lua/ime_translate/backend.lua` | Three adapters (openai / libretranslate / anthropic) + curl runner + error classification + the `prewarm` no-op |
| `rime/lua/ime_translate/session.lua` | Context property accessors, draft reading, snapshot comparison, the prompt text for the current phase |
| `rime/lua/ime_translate/decide.lua` | Pure-function key decisions. Touches no rime global, does no IO |
| `rime/lua/ime_translate_shared.lua` | Process-wide read-only singleton: settings, warnings, api_key |
| `rime/lua/ime_translate_processor.lua` | Thin glue, **sole commit owner**; writes and clears the prompt |
| `rime/luna_pinyin_translate.schema.yaml` | The translation schema: `fluid_editor` + one lua component, the processor |
| `rime/default.custom.yaml` | Schema list + the forward `Ctrl+Shift+T` binding |
| `rime/ime_translate.yaml` | User config defaults |
| `launchd/*.plist` | Resident backend services |
| `scripts/install.sh` / `scripts/run_tests.sh` / `scripts/eval.sh` | Install, test, blind eval |
| `tests/test_*.lua` | Headless unit tests |
