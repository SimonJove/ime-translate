# Implementation plan — feature 005, a more reliable Enter

> **For agentic workers:** load the `plan-execution` skill and work one task at
> a time. Run `./scripts/progress.sh` as `PROGRESS_FEATURE=005 …`.

**Goal.** Enter gives a usable English sentence more often, and sooner:
- a cloud failure falls back to the local backend on the same Enter;
- Enter after an error translates again instead of committing the Chinese;
- a draft already translated by a slot is not sent to it again;
- `translate` keeps URLs intact.

**Architecture.**
- **`config`** caps `cloud_timeout_ms` at 2000, keeping 500 ms of the 2500
  budget for the fallback.
- **`backend`**: the `libretranslate` adapter swaps each URL for a
  placeholder `X_n` before the request and restores it after.
- **`cache`** (new): a small most-recent-first store of successful
  translations, keyed by slot and draft. One per Lua state, in `shared`.
- **`route`** (new): the one place that decides which slot answers an Enter:
  the cache, the active slot, then — for the cloud only — the local slot with
  a 500 ms timeout. Pure except for the injected runner.
- **`decide`**: Enter in `error` returns `translate`.
- **The processor** calls `route.translate` instead of `backend.translate`, and
  records whether the result is a fallback; `session.prompt` shows
  `  ☁✗ -> …` for one.

**Design.** [architecture.md §5.2, §5.6, §6.1, §6.2, §6.4](../../../design/architecture.md),
[backend.md §7.5, §8.1–8.3, §9](../../../design/backend.md). The decisions:
[decisions.md](../../../design/decisions.md), "Feature 005 designed".

## Global constraints

- English in every file, with Chinese only as data.
- Lua 5.4, with no dependencies.
- `commit_text` appears only in the processor.
- Session state lives in Context. The cache is process-wide by §6.1's test.
- Never eat text: no path added here commits or clears.
- The worst-case freeze after Enter stays 2500 ms.
- A local failure is never sent to the cloud.

## Tasks

| # | Task | Depends on | Files |
|---|---|---|---|
| 1 | `cloud_timeout_ms` capped at 2000 | — | `config.lua`, `tests/test_config.lua` |
| 2 | The URL guard in the `libretranslate` adapter | — | `backend.lua`, `state.lua`, their tests |
| 3 | The cache and the route, with the cloud-to-local fallback | 1 | `cache.lua`, `route.lua`, `ime_translate_shared.lua`, their tests |
| 4 | Enter retries in `error`; the processor uses the route; the fallback prompt | 2, 3 | `decide.lua`, `session.lua`, `ime_translate_processor.lua`, their tests |
| 5 | README, template; real-machine smoke (manual) | 4 | `README.md`, `rime/ime_translate.yaml`, `docs/smoke-report-005.md` |
