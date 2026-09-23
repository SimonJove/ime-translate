# Implementation plan — feature 006, a hint when Enter locks letters

> **For agentic workers:** load the `plan-execution` skill and work one task at
> a time. Run `./scripts/progress.sh` as `PROGRESS_FEATURE=006 …`.

**Goal.** After Enter locks English letters in a draft, the preedit shows
`  [en]` until the next key press, so the user can see the letters were kept
and the mode is still Chinese.

**Design.** [architecture.md §5.5, §6.4](../../../design/architecture.md); the
decision: [decisions.md](../../../design/decisions.md), "Feature 006 designed".

## Global constraints

- English in every file, with Chinese only as data (`state.lua`, tests,
  backticks in docs).
- `commit_text` only in the processor; the hint commits nothing and clears
  nothing but itself.
- A prompt holding a translation or an error is never touched.

## Tasks

| # | Task | Depends on | Files |
|---|---|---|---|
| 1 | The hint: shown by the lock, cleared by the next key press | — | `state.lua`, `ime_translate_processor.lua`, `tests/test_state.lua`, `tests/test_processor_mixed.lua` |
| 2 | README; real-machine smoke (manual) | 1 | `README.md`, `docs/smoke-report-006.md` |
