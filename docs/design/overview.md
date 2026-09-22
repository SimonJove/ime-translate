# Design overview

Read this first. It is the 30-second model of the whole project. Every other
file under `docs/design/` is detail you load only when you need it.

**Status**: verified, v1 usable (2026-09-22).
- **Feature 001** (translate on Enter) is built, measured by the spike and by real-machine smoke runs.
- **Feature 002** (mixed Chinese and English) is built.
- **Open decisions:** none. D2 and D6 were decided on 2026-09-22 ([decisions.md](decisions.md)).
- **Previously:** Plan A′ locked; awaiting Phase 0 spike verification.

## What it is

A macOS input method that translates as you type: you type Chinese, press
Enter, and what lands in the application is English. The IME owns the draft for
its whole life; the application only ever receives the final result.

Hard constraint that decides the shape: macOS exposes no extension API for
system input methods, so there is no way to bolt onto Apple Pinyin. Covering
every application means shipping a third-party IME. We build on Rime/Squirrel
rather than writing a pinyin engine.

## The shape of Plan A′

A separate Rime schema `luna_pinyin_translate`, side by side with the normal
`luna_pinyin` and sharing its dictionary and user dictionary:

- `fluid_editor` replaces `express_editor`, so the composition does not
  auto-commit. **Rime's own composition is the Chinese draft buffer** — we do
  not build one.
- Committing goes through `engine:commit_text()` in the processor only. It
  never travels through candidate selection or segment concatenation.
- Session state lives in `Context` properties, so it is per-session by
  construction.
- `Ctrl+Shift+T` switches schemas via Rime's native `key_binder`; there is no
  toggle logic in Lua.

**The governing principle: display and commit are fully separated.** The
translator and filter only render things for the user to look at; the processor
alone may commit. Both fatal defects of the original Plan A came from letting a
candidate do both jobs at once.

## The five invariants

These are not style preferences. Each one has a failure mode that a unit test
cannot catch.

1. **Never eat text** — before any `ctx:clear()`, a `commit_text()` must
   already have committed either the Chinese draft or the English translation.
   ([architecture.md §6.3](architecture.md))
2. **One commit exit** — `engine:commit_text()` appears only in
   `ime_translate_processor.lua`. ([architecture.md §3.1](architecture.md))
3. **Session state only in `Context`** — librime-lua gives every registered
   component one shared Lua state, so module-level state leaks across every
   input session. ([architecture.md §6.1](architecture.md))
4. **Shell escaping only via `json.shq`** — `string.format("%q", …)` is Lua
   literal escaping; the double quotes it produces still let `$()` and
   backticks expand. The API key travels this path.
   ([backend.md §7.3](backend.md))
5. **Secrets never in the repo or `~/Library/Rime/`** — that directory is
   rescanned wholesale on "Redeploy" and is routinely pushed to GitHub as
   config sync. ([backend.md §7.3](backend.md))

The first three are enforced mechanically by `.claude/hooks/` and
`.githooks/pre-commit`; all five are review dimensions in
`.claude/skills/task-review/SKILL.md`.

## The gate

Three spike checks gate the whole tree:

- **S1** — under `fluid_editor`, does segment-by-segment selection really not
  commit to the application?
- **S3** — does `engine:commit_text()` exist and accept arbitrary text?
- **S11** — does the Enter → preview → Enter loop close, in both draft states,
  through at least one display mechanism?

**S1 or S3** falsified and Plan A′ is dead: stop, return to design, and evaluate
Plan B′ (Lua-owned draft buffer) — **not** a jump straight to forking Squirrel.
**S11** falsified and §6.1–§6.2 go back to design review before any
implementation continues — A′ itself may still stand. See
[architecture.md §3.5](architecture.md) for the ratchet rule and
[testing.md §10.2](testing.md) for all of S1–S14.

The gate passing proves the foundations, not the product. A design review on
2026-09-20 found that the Enter → preview → Enter loop does not close as §6 is
written, and that Squirrel dumps the draft as raw pinyin on focus loss
([risks.md §12](risks.md) R10, R11). S11–S13 measure those; S11 joined the gate
by decision D3, and two decisions stay open behind the rest
([decisions.md §13](decisions.md), D1–D2).

Until `docs/features/001-zh-en-ime/progress.json` records `gate: pass`, writes to `rime/` and `tests/`
are refused.

## Where things are

| File | Contains | Load it when |
|---|---|---|
| [requirements.md](requirements.md) | §1–§2 background, requirements, non-goals | Deciding whether something is in scope |
| [architecture.md](architecture.md) | §3–§6 plan choice, components, dataflow, key bindings, session state | Touching any Lua component |
| [backend.md](backend.md) | §7–§9 backend contract, three adapters, error codes, latency, config | Touching `backend.lua`, `config.lua`, adapters |
| [testing.md](testing.md) | §10 unit tests, spike S1–S14, compat matrix, quality eval | Running the spike or writing tests |
| [risks.md](risks.md) | §11–§12 install, risk register, machine environment | Planning, or when something surprising happens |
| [decisions.md](decisions.md) | §13 decision log, open decisions D1–D2 | Asking "why is it like this" |
| [evidence.md](evidence.md) | §14 backend evaluation evidence | Choosing or changing a backend |
| [upstream.md](upstream.md) | §15 what librime, librime-lua and Squirrel actually do, read from source | Relying on any engine behaviour — before assuming it |

Section numbers are stable IDs. `docs/features/001-zh-en-ime/plan/` cites them as `design §X.Y`, and
`scripts/design-section.sh 6.2` prints any one of them without your reading a
whole file.
