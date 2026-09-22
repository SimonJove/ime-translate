# Test strategy

Part of the design set — start at [overview.md](overview.md).

## 10. Test strategy

### 10.1 Lua unit tests (headless)

Mock `io.popen`. Cover:

- Every branch of `decide.decide()`: Enter in all three phases, Shift+Enter,
  Esc, the `invalidate_and_pass` catch-all for any other key, release events,
  Enter with modifiers.
- `session`'s draft snapshot comparison: match, mismatch, snapshot missing.
- `state`, `config` (including all three `allow_remote` combinations),
  `backend` (three adapters × eight error codes), `json`.

The processor's key-decision logic must be a **pure function**
`decide(key, phase, settings) -> action` that touches no rime global and does no
IO. The glue layer only does "read context → call decide → execute action".

### 10.2 Phase 0 spike (one-off, code thrown away afterwards)

Verifies the unproven semantics A′ rests on. **S1, S3 and S11 are
life-or-death** — S11 joined them by decision D3, 2026-09-20.

| # | Check | Criterion |
|---|---|---|
| **S1** | Under `fluid_editor`, does segment selection really not commit to the app? | Type `今天有点累`, select segment by segment; the app's input box must only ever show preedit. **Early commit → A′ does not exist** |
| **S2** | Which path does Chinese punctuation take: merged into the composition, or committed directly? | Committed directly → enable the fallback in [architecture.md §5.3](architecture.md). **Expected from source: committed directly** ([upstream.md §15.2](upstream.md) F4) — so the same step also applies the §5.3 fallback and checks that the mark then stays in the draft |
| **S3** | Does `engine:commit_text()` exist and commit arbitrary text? | Committing a fixed English string succeeds. **Unavailable → A′ does not exist** |
| **S4** | Are `ctx:set_property` / `get_property` exposed? | Read-write round trip. Unavailable → fall back to a module table keyed by engine + `fini` cleanup |
| **S5** | Can `key_binder`'s `select:` switch **both ways** with one hotkey? | Unavailable → fall back to the `Ctrl+\`` schema menu |
| **S6** | Does changing a comment via `ShadowCandidate` take effect? | Determined how the filter was written. Moot since D1: there is no filter, the error shows in the prompt |
| **S7** | Long inline preedit (30+ chars) in terminals / WeChat | Broken → downgrade that app to a floating preedit |
| **S8** | Backend latency baseline: translate vs apfel over the §10.4 sentence set | Decides the default backend and `timeout_ms` |
| S9 | Can `io.popen` run curl from inside rime-lua? | Prerequisite |
| S10 | Does multi-file `require` work? | Prerequisite; decides whether modules can live in subdirectories |
| **S11** | Does the **Enter → preview → Enter loop** close? A fake translation, no backend; run with the draft fully confirmed and with the last segment open, once displaying through a candidate (§6.2 as written) and once through `segment.prompt` | The translation is visible after the first Enter, and the second Enter commits exactly it, in **both** states, for at least one mechanism — that mechanism becomes the constant Tasks 7 and 9 build on. Neither → the gate fails: §6.1–§6.2 go back to design review before any implementation continues ([risks.md §12](risks.md) R10) |
| S12 | With a 30+ character draft: Cmd+Tab away and back, click inside the same text box, click another window, switch input source and back | Record what lands in the box — nothing, raw pinyin, or Chinese — and whether the draft is still editable. Input to decision D2 (R11) |
| S13 | Block inside the processor on Enter for 1.5 s, then 4 s, in WeChat, Slack and Terminal | Enter must not reach the application; keys typed during the stall arrive afterwards, in order. Enter reaching the application at 1.5 s → the synchronous model does not stand as designed; only at 4 s → the cloud `timeout_ms` ceiling must sit below the observed threshold (R12) |
| S14 | Can mixed content be **typed into** the draft: an identifier with capitals, a URL, an emoji | Record what the composition holds and what `get_commit_text()` returns for each (R13) |

> **Verdicts (spike, 2026-09-20; [spike-report.md](../spike-report.md)), written
> back by 001 Task 12:**
> - **The life-or-death three.** S1 pass, S3 pass, and S11 pass with
>   `segment.prompt` (D1).
> - **S2** failed as predicted, and the §5.3 fallback passes.
> - **Pass:** S4, S5, S9 and S10. S6 passes too, but no longer governs
>   anything (D1).
> - **S7** renders fully in Terminal (the floating preedit, `no_inline`), in
>   WeChat and in TextEdit. Slack is unverified.
> - **S8:** `translate` has P95 21 ms warm and 93 ms cold, and apfel is
>   unavailable (D4).
> - **S12:** focus loss commits the raw key string (F11 confirmed; accepted by
>   D2).
> - **S13:** the synchronous model holds below about 2.5 s.
> - **S14:** recorded. Mixed content was later made typable by feature 002
>   (§5.5).

**Order**: S9/S10 → S3/S4 → S1/S2 → S5/S6/S7 → S11 → S12/S13/S14 → S8. Backend
selection comes last, because if the gate fails it does not matter which
backend it is.

S11–S14 were added by the design review of 2026-09-20. S1 and S3 are, by source
reading, the *safest* assumptions in the set
([upstream.md §15.2](upstream.md) F1); the ones that can actually overturn the
design are S11–S13. **So S11 joined S1/S3 in the recorded gate, and S11–S14 all
entered Task 1's acceptance list** (decision D3,
[decisions.md §13](decisions.md)).

Falsification does not mean the same thing for all three. S1 or S3 kills
Plan A′. S11 sends §6.1–§6.2 back to design review with the rest of A′ intact.
S13, S12 and S14 are acceptance items but **not** gate items: S13 is pass/fail
only at 1.5 s — at 4 s a failure is a recorded threshold for the cloud
`timeout_ms` ceiling — and S12 and S14 are record-only by construction, so what
they require is that the report holds the observation.

**Recording requirement**: the spike report must write down the actual Squirrel,
librime, librime-lua and schema versions. All later re-verification is measured
against those versions.

### 10.3 Manual acceptance and compatibility matrix

Build an application × check-item matrix and record each cell as
**supported / needs config / unverified**. Do not substitute "an IME covers
everything by nature" for compatibility evidence.

Applications: WeChat, Slack, Chrome (Gmail / Notion), Terminal, Notes, iMessage.

Check items:

1. Inline preedit rendering (including a 30+ character draft)
2. Segment selection does not commit early
3. Translation candidate display (long-translation truncated preview, full text
   on commit)
4. Enter commits the correct English **and does not pass through as send**
5. **Two or more consecutive translations** (covers the reset)
6. `Shift+Enter` commits the Chinese draft
7. After Esc, the draft survives intact and stays editable
8. Failure fallback (stop the backend service)
9. **After the translation appears: keep typing / backspace / move cursor /
   change candidate / click a candidate with the mouse** — none leaves a stale
   translation behind
10. **Typing during the wait**: keys pressed while frozen are neither lost nor
    reordered afterwards
11. **Focus change**: switch to another app and back; draft and state do not
    cross over — **and record what landed in the box the draft was in**.
    Isolation is not survival: Squirrel commits the raw key string on
    deactivation ([risks.md §12](risks.md) R11)
12. **Switching input method**: switch to the system English IME and back
13. The schema hotkey works both ways and the menu-bar schema name is correct
14. **Mixed content is typable**: an identifier with capitals, a URL and an
    emoji entered into the draft from the keyboard, not fed to the backend
    through curl (R13)

### 10.4 Quality evaluation

A fixed set of 30 real chat sentences from the user, used for a **blind eval of
translate (NMT) vs apfel (LLM)** to pick the default backend. It must cover four
categories: colloquial (`哈哈哈可以，就这么定了`), containing code identifiers,
containing URLs, containing emoji.

> **Revised by decision D4 (2026-09-20).** apfel is unavailable on the
> development machine, so the eval no longer picks between translate and apfel:
> `translate` is the default, and the eval measures its quality on the set —
> against a local model server only if one is set up.
>
> **As run in 001 Task 11 (2026-09-22).** The set is 30 sentences in five
> categories: chat, code, url, emoji, and mixed Chinese-English.
> - **Where they come from.** 12 come from the original plan. The other 18
>   were composed by the agent, by the user's decision, not taken from real
>   chat. They are marked so in `eval/sentences.txt`.
> - **Results.** 21 of 30 acceptable; P50 20 ms, P95 37 ms
>   ([compat-matrix.md](../compat-matrix.md)).

The eval exercises the **backend** only — sentences reach it through curl.
Whether the last three categories can be typed into a `fluid_editor` composition
in the first place is a separate question, S14. A category that cannot be typed
is not a reason to pick one backend over the other.
