# Backend, errors, latency, config

Part of the design set — start at [overview.md](overview.md).

## 7. Translation backend contract

### 7.1 Abstract interface (backend agnostic)

```
translate(settings, text) -> ok:boolean, translation_or_errcode:string
prewarm(settings, text)   -> nil        (no-op in v1, see §8.3)

error codes: conn_refused | timeout | http_error | bad_json | empty | too_long
           | auth_error | rate_limited      ← cloud only
```

Shared by every backend: a hard timeout ceiling; input longer than `max_chars`
goes straight to the failure fallback. The adapter decides request shape and
authentication; `M.translate` only handles the length check, calling the runner,
and classifying exit codes and HTTP statuses.

### 7.2 Tiered trust model

| Tier | Condition | Validation |
|---|---|---|
| **Local (default)** | `base_url` is `127.0.0.1` / `localhost` | No key needed; `http://` allowed |
| **Cloud** | Requires `allow_remote: true` | **`https://` enforced** (non-loopback over `http://` is always refused); an API key must be obtainable; menu bar and log mark it "cloud" explicitly |

**Why an explicit switch stays**: the input method sees every character the user
types. Turning cloud on means all Chinese input goes to a third party — that
decision must be made deliberately by the user, not happen quietly because one
`base_url` line was edited wrong.

### 7.3 API key handling (hard requirement)

**The API key never goes into `~/Library/Rime/ime_translate.yaml`.** The Rime
user directory is rescanned wholesale on "Redeploy", and many users push all of
`~/Library/Rime` to GitHub as config sync — the key would inevitably leak.

```
security add-generic-password -s ime-translate -a <backend> -w         # user stores it once; -w last prompts, keeping the key out of shell history
security find-generic-password -s ime-translate -a <backend> -w        # processor reads at startup
```

The config file contains only `api_key_account: <backend>`, never the secret.
Logs and error messages never print the key.

> **Implementation constraint**: building that shell command must use POSIX
> single-quote escaping (`json.shq`), **not Lua's
> `string.format("%q", ...)`** — that is Lua literal escaping, and the double
> quotes it produces still let `$()` and backticks expand in a shell.

### 7.4 Adapter A: OpenAI-compatible (apfel local / OpenAI / DeepSeek / Kimi / GLM)

One adapter covers five vendors, differing only in `base_url` / `model` /
`api_key` (lookup table in [evidence.md §14.5](evidence.md)).

- `POST {base_url}/chat/completions`
- Auth: none locally; `Authorization: Bearer <key>` for cloud
- System prompt goes in `messages[0].role = "system"`
- Take `choices[0].message.content`, trim, return
- Local default: `http://127.0.0.1:11434/v1`, model `apple-foundationmodel`

  > **Not the product default (decision D4, 2026-09-20).** apfel cannot run on
  > the development machine — Apple does not make FoundationModels available
  > for its device region — and answers every completion with HTTP 503
  > while `/v1/models` still returns 200. The default backend is `translate`
  > (§7.5). This adapter stays for apfel on eligible machines and for cloud
  > vendors.
- System prompt (default, configurable):

  ```text
  你是翻译器。把用户的中文翻译成自然、简洁、适合即时聊天语境的英文。只输出译文——不要解释、不要引号、不要前缀。保留语气、emoji、数字、URL、代码标识符和换行。如果文本基本没有中文，原样返回。
  ```

  The prompt itself is Chinese on purpose: it addresses a model translating
  Chinese input, and rewriting it in English would change the artifact under
  test. It is a data value, not project prose — which is why it sits in a code
  block, the form `checks_language` requires for quoted Chinese data.

### 7.5 Adapter B: LibreTranslate-compatible (`translate`, local NMT)

- `POST {base_url}/translate`, default `http://127.0.0.1:8989`
- Request `{"q": <text>, "source": "zh", "target": "en"}`
- No prompt, no temperature (NMT output is deterministic)
- The language identifier is **`zh`**, not `zh-Hans` (measured,
  [evidence.md §14.2](evidence.md))

### 7.6 Adapter C: Anthropic Messages API

Four differences from OpenAI shape:

- `POST {base_url}/messages`, default `https://api.anthropic.com/v1`
- Auth: `x-api-key: <key>` **plus `anthropic-version: 2023-06-01` (required
  header)**
- **The system prompt is a top-level `system` field**, not part of `messages`
- **`max_tokens` is required**
- Reading the result: walk `content[]` and take the block with
  `type == "text"` — **do not blindly take `content[0]`**, a thinking block can
  come first
- Handle `stop_reason == "refusal"`

```json
{
  "model": "claude-haiku-4-5",
  "max_tokens": 1024,
  "system": "…only output the translation…",
  "messages": [{"role": "user", "content": "收到，我马上看"}]
}
```

**Recommended model: `claude-haiku-4-5` ($1/$5 per million tokens)** —
translation is a light task; Opus is slower, costlier, and adds thinking blocks
and refusals to handle. Pricing table in [evidence.md §14.5](evidence.md).

### 7.7 `temperature` cannot be sent unconditionally

`temperature` / `top_p` / `top_k` have been removed on Claude Opus 5, Sonnet 5
and Opus 4.7/4.8; sending them returns 400. **Whether `temperature` is carried
is the adapter's decision, not an unconditional field of the shared Settings.**

## 8. Error handling and latency

### 8.1 Error fallback

Governing rule: **never eat text.** Any failure → `phase = error`, the processor
writes `✗ reason` into the last segment's prompt, after the draft in the preedit
([architecture.md §6.4](architecture.md)), and the draft stays intact in the
composition. Enter commits the Chinese draft; Esc returns to idle to keep
editing; Enter again retries. No automatic retry in v1.

| Code | Fault | Message |
|---|---|---|
| `conn_refused` | Service not running / connection refused | `✗ 翻译服务未启动` |
| `timeout` | Timed out | `✗ 翻译超时` |
| `http_error` / `bad_json` / `empty` | Transport failure / unparseable response / empty response or model refusal | `✗ 翻译失败` |
| `too_long` | Over `max_chars` | `✗ 文本过长` |
| `auth_error` | 401/403: key missing, invalid, or out of quota | `✗ 密钥无效` |
| `rate_limited` | 429 | `✗ 请求过频` |

(Message strings are Chinese because they are shown to the user in the candidate
window of a Chinese IME. They are UI copy, not project prose.)

`auth_error` and `rate_limited` are separate codes because the user's action
differs completely: fix the key, versus wait.

> **Why the prompt and not a candidate's comment (D1, 2026-09-21).** The first
> version hung the reason on the first candidate through a `ShadowCandidate`
> filter. With every segment confirmed there is no candidate to hang it on —
> spike S11 showed no candidate window at all in that state — so the error would
> be invisible and Enter would commit the Chinese with no reason given. The
> prompt shows in both states. S6 no longer governs anything.

### 8.2 Latency: two metrics that must stay separate

| Metric | Definition | Target |
|---|---|---|
| **Typing latency** | Response to each keystroke: pinyin, selection, backspace | **Indistinguishable** from the normal schema. Translation mode does no IO on the typing path |
| **Confirmation latency** | Enter until the translation appears; the user waits through all of it | P95 ≤ 800 ms locally |

"Never block typing" means precisely: **zero added cost while typing; the freeze
happens only on that one Enter.**

> **Under a synchronous blocking model, the timeout value *is* the worst-case
> freeze duration.** It bounds the wait; it does not guarantee smoothness.

So the local default `timeout_ms` is **1500** — past one second the experience
has already collapsed, and waiting until three seconds to fall back only
prolongs a bad experience. Cloud opt-in may relax it to 4000, but the config
comment must state that this number equals the seconds the IME freezes after you
press Enter.

### 8.3 Pre-translation: interface reserved, not implemented in v1

`backend.prewarm(settings, text)` is an empty function. The hook point is
decided (the processor's `invalidate_and_pass` branch) but v1 does not wire it.
Two limits recorded up front, so it is not later mistaken for a silver bullet:

- **Hits are not guaranteed** — one character changing at the end of the draft
  expires the existing result. Landing it for real also needs debouncing,
  request coalescing, cache versioning and discarding stale results.
- **Cloud pre-translation would also send drafts the user never commits**, a
  larger privacy surface than "send on Enter". It would need its own switch.

Neither "a custom daemon is required" nor "pre-translation is the only
mitigation" is a proven conclusion. Going async also requires designing how a
background result notifies the IME, how it triggers a UI refresh, and how to
verify the session and focus are still valid — simply adding a daemon does not
supply that chain ([evidence.md §14.3](evidence.md)). None of it is decided
before S8 measures the real latency distribution.

## 9. Configuration

The processor reads one YAML at startup (`~/Library/Rime/ime_translate.yaml`).
Logs go to `~/Library/Logs/`.

| Key | Meaning |
|---|---|
| `backend` | `openai` \| `libretranslate` \| `anthropic` — picks the adapter |
| `base_url` / `model` / `prompt` | The backend triple |
| `allow_remote` | Default `false`. When false, any non-loopback `base_url` is refused; when true, non-loopback must be `https://` |
| `api_key_account` | The Keychain account name. **Never the secret itself** |
| `max_tokens` | Needed only by the anthropic adapter |
| `timeout_ms` | Default 1500 (local). **Equals the worst-case freeze after Enter** |
| `max_chars` / `debug_log` | Character ceiling / debug log switch |

- `max_chars` counts **characters**, not bytes. Lua's `#s` is bytes and Chinese
  takes 3 bytes in UTF-8, so using it directly turns 2000 characters into
  roughly 666.
- The schema-switch hotkey lives in `default.custom.yaml`'s `key_binder`,
  **not in this file** — it has been handed back to native Rime.
