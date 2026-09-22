# Backend evaluation evidence

Part of the design set — start at [overview.md](overview.md).

## 14. Evidence behind the backend decisions

This section supports [backend.md §7](backend.md). The conclusions already live
there; what is kept here is **the measurements that produced them**, so they can
be re-verified or revisited later.

### 14.1 The two local backend candidates

Both are sibling projects by the same author (Arthur-Ficial).

| | apfel | translate |
|---|---|---|
| Engine | AFM large model, generative | Apple Translation framework, purpose-built NMT |
| Protocol | OpenAI-compatible, `:11434` | DeepL / LibreTranslate / Google v2, `:8989` |
| Adapter here | [backend.md §7.4](backend.md) (A) | [backend.md §7.5](backend.md) (B) |
| Latency | Not measured | Claims cold start <200 ms, >500 sentences/s, <300 MB RAM (**vendor claim, not measured by this project**) |
| Output controllability | Can refuse, add prefixes, add explanations; constrained only by prompt | **Deterministic output; refusal is impossible** |
| Tone fidelity | Strong (can be asked for "chat register, preserve tone") | Skews formal; colloquial quality pending the blind eval ([risks.md §12](risks.md) R4) |
| Preserving URLs/code/emails | Hope, via prompt | **Deterministic in code** (`TranslationMasker`, see §14.4) |
| License | — | MIT, Swift 6, macOS 26+ / Apple Silicon |

Each has real strengths. **Which one is the default is decided jointly by the
30-sentence blind eval ([testing.md §10.4](testing.md)) and the S8 latency
baseline**, not presupposed. All three adapters are already fixed in
[backend.md §7](backend.md), so the choice does not change implementation
effort.

### 14.2 Headless TranslationSession works (verified on this machine)

macOS 26 added a **direct initializer** to `TranslationSession`, removing the
need for a SwiftUI `.translationTask` host view — historically the biggest
barrier to using Apple's translation framework. The wrapper in `translate`'s
`Sources/translate/Models.swift`:

```swift
public static func installedSession(source:target:) -> TranslationSession {
    if #available(macOS 26.4, *) {
        return TranslationSession(installedSource: source, target: target,
                                  preferredStrategy: .lowLatency)
    } else {
        return TranslationSession(installedSource: source, target: target)
    }
}
```

**Implication**: Apple NMT can be called from any Swift process (CLI, daemon, or
the IME itself) in about 15 lines. This is also why
[architecture.md §3.3](architecture.md) says C′ costs less than first estimated.

Probe result — single file, zero third-party dependencies, only
`import Translation`:

```
$ swiftc -O main.swift -o probe
=== BUILD OK ===
$ ./probe
zh-Hans -> en status: supported
Chinese entries in supportedLanguages: ["zh-TW", "zh"]
```

| Item | Result |
|---|---|
| Headless compile and run | ✓ No SwiftUI, app bundle, SPM or signing needed |
| `Translation.framework` | Present; `_Translation_SwiftUI.framework` is a **separate** framework ✓ |
| `zh -> en` model status | `.supported` (supported, **not yet downloaded at probe time**) |
| Chinese identifier | **`zh` and `zh-TW`**; `zh-Hans` is **absent** from `supportedLanguages` → [backend.md §7.5](backend.md) uses `zh` |

**Still unmeasured**: real zh→en latency and quality — that needs the one-off
model download (~100–200 MB, possibly through the System Settings GUI, i.e.
[risks.md §12](risks.md) R9). That is exactly what S8 is for.

### 14.3 Hard constraint: rime-lua's pipes are one-way

**`io.popen` is unidirectional** (read or write, not both), and standard Lua has
no `popen2`. That locks the shape of any "resident translation service" to:

> A separate daemon process, plus a cheap client per request (curl / nc, roughly
> 10–20 ms of process tax)

**Corollary: a custom daemon buys no extra performance** — the shape is
identical to the current `curl → HTTP`. Rewriting it would buy dependency
slimming, protocol autonomy and pre-translation capability, **not latency**.
This is the technical basis for [backend.md §8.3](backend.md) saying "a custom
daemon is required" is not a proven conclusion.

### 14.4 If a custom daemon is ever built: reuse inventory

`translate` is MIT and can be vendored directly. Net reuse is about **280 lines
of Swift**, while shedding ~1400 lines and two third-party dependencies
(ArgumentParser, Hummingbird).

| Piece | Lines | Value | Handling |
|---|---|---|---|
| `TranslationSupport` (Models.swift:162-201) | 40 | ★★★ the key wrapper in §14.2 + the 26.4 lowLatency branch | Copy as is |
| `ModelManager.status/prepare` | ~30 | ★★★ model availability and download | Copy, trimmed to one language pair |
| `TranslationMasker` (Translator.swift:141-320) | 180 | ★★★ protects backtick code blocks / URLs / emails, splits on newlines | **Copy as is** |
| `AppleTranslator.translate` | 50 | ★★ main flow | Trim to ~25 lines |
| `TranslateError` | 45 | ★ error codes | Map onto [backend.md §7.1](backend.md)'s codes, ~15 lines |
| Server / DeepL / Google / LibreTranslate / Stream / Output / FormDecoder / CLI / Detect | ~1400 | ✗ three API compatibility layers + CLI parsing | Discard |

`TranslationMasker` is especially worth copying: the list in
[backend.md §7.4](backend.md)'s prompt — preserve emoji, numbers, URLs, code
identifiers and newlines — is pure hope in an LLM approach, but **deterministic
code** here; and rolling it yourself invites boundary bugs (nested backticks,
unclosed fences, range merging).

**But not in v1**: §14.3 already shows a custom daemon brings no latency gain,
and its one irreplaceable value (pre-translation) is of unproven feasibility per
[backend.md §8.3](backend.md).

### 14.5 Cloud vendor lookup

Four of the five share [backend.md §7.4](backend.md)'s OpenAI adapter, differing
in three fields. Only Anthropic needs its own adapter
([backend.md §7.6](backend.md)).

| Vendor | Adapter | base_url (per each vendor's own docs) | Auth header |
|---|---|---|---|
| **apfel (local)** | §7.4 | `http://127.0.0.1:11434/v1` | none |
| OpenAI | §7.4 | `https://api.openai.com/v1` | `Authorization: Bearer <key>` |
| DeepSeek | §7.4 | `https://api.deepseek.com/v1` | `Authorization: Bearer <key>` |
| Kimi (Moonshot) | §7.4 | `https://api.moonshot.cn/v1` | `Authorization: Bearer <key>` |
| GLM (Zhipu) | §7.4 | `https://open.bigmodel.cn/api/paas/v4` | `Authorization: Bearer <key>` |
| **Anthropic** | §7.6 | `https://api.anthropic.com/v1` | `x-api-key: <key>` + `anthropic-version: 2023-06-01` |

Anthropic model pricing (per million tokens, input/output):

| Model | model id | Price | Notes |
|---|---|---|---|
| Claude Haiku 4.5 | `claude-haiku-4-5` | **$1 / $5** | **The recommendation in [backend.md §7.6](backend.md)**: fastest, cheapest, and supports `temperature` |
| Claude Sonnet 5 | `claude-sonnet-5` | $3 / $15 | `temperature` unavailable ([backend.md §7.7](backend.md)) |
| Claude Opus 5 | `claude-opus-5` | $5 / $25 | `temperature` unavailable; **thinking on by default**, pure wasted latency for translation |

### 14.6 References

- [Arthur-Ficial/translate](https://github.com/Arthur-Ficial/translate) (MIT)
- [Arthur-Ficial/apfel](https://github.com/Arthur-Ficial/apfel)
- [apfel OpenAI compatibility docs](https://github.com/Arthur-Ficial/apfel/blob/main/docs/openai-api-compatibility.md)
  — verified: model name `apple-foundationmodel`, port `11434`,
  `/v1/chat/completions`, matching [backend.md §7.4](backend.md)'s defaults
  word for word ✓
