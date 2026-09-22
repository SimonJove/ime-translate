# ime-translate

A Chinese → English translation input method for macOS, built on Rime/Squirrel.
Type Chinese, press Enter to see the English, and press Enter again to commit
it to the application. Translation is local by default: nothing leaves the
machine.

Personal use. The design is in [`docs/design/`](docs/design/overview.md).

## Install

```bash
brew install --cask squirrel                  # the IME host
brew install arthur-ficial/tap/translate      # the default backend: Apple's on-device NMT
./scripts/install.sh                          # Lua, schema and config into ~/Library/Rime,
                                              # and the translation service into launchd
```

Then, once per machine:
1. **Add Squirrel.** System Settings → Keyboard → Input Sources → add
   Squirrel. If it is missing, log out and in once.
2. **Download the model.** System Settings → General → Language & Region →
   Translation Languages → download Chinese → English. `translate --install`
   cannot do this from the command line; it needs the confirmation window.
3. **Nothing else.** `install.sh` ends with a redeploy, which loads the new
   version. No restart is needed.

`install.sh` is idempotent: running it again changes nothing that is already
right. It never overwrites a `default.custom.yaml` of your own, and it lays down
`ime_translate.yaml` only when it is missing.

## Use

**Switching schemas.** `Ctrl+Shift+T` switches between `朙月拼音·简化字`
(`luna_pinyin_simp`) and the translation schema, `朙月拼音·译`
(`luna_pinyin_translate`). A new input box starts in whichever you used last.
Switching schemas with a draft open discards the draft: commit it first.

**Translating.** In the translation schema you type a draft; nothing is
committed while you type. Select the Chinese (Space or a number) before
pressing Enter to translate. Enter on pinyin still unselected turns it into
English letters instead: `nihao` ⏎ ⏎ commits `nihao`.

| Key | With a draft | With the English showing |
|---|---|---|
| Enter | with everything selected: translate, and the English shows after the draft. With pinyin still unselected: keep it as English letters (see below) | commit the English |
| Shift+Enter | commit the Chinese, untranslated | commit the Chinese |
| Esc | cancel the draft | drop the English, keep the draft |
| Right Option, tapped alone | switch between the local and the cloud backend | drop the English, switch; Enter translates again with the other one |

Sending is always yours: the IME never presses Enter for you. The Enter that
commits the English is taken by the IME, so it does not send. Seen in WeChat;
other chat apps are not yet checked (see the compatibility matrix). Your next
Enter sends.

**Mixed Chinese and English.**
- **Pinyin, then Enter:** the letters you typed stay in the draft as English.
  Select the Chinese first (Space or a number), then Enter translates.

  `jintian`␣ `readme`⏎ `haode`␣ → `今天readme好的`, then ⏎ → the English
  keeps `readme`.
- **Space, when nothing is left to select,** adds a space: `pull`⏎ ␣
  `request`⏎.
- **A draft with no Chinese at all** is committed as is: `readme`⏎ ⏎.
- **A lone tap of Shift** switches to English mode, for English with digits
  or punctuation such as `v2.0`, and back. In English mode Enter translates at
  once.
- **Capitals:** Shift+letter or Caps Lock. Caps Lock only types capitals here;
  it never switches mode or clears the draft.
- **Fixing an English word:** BackSpace turns it back into pinyin, and Enter
  makes it English again.

## Configure

`~/Library/Rime/ime_translate.yaml`, `key: value` per line. After editing,
**redeploy**, with no draft open. Either use the input menu's Deploy
(`重新部署`), or run:

```bash
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload
```

The change takes effect a few seconds later. No restart is needed.

| Key | Default | Meaning |
|---|---|---|
| `backend` | `libretranslate` | `libretranslate` (the local `translate` service), `openai` or `anthropic` |
| `base_url` | `http://127.0.0.1:8989` | where the backend listens |
| `model` | empty | the model, for `openai` and `anthropic` |
| `timeout_ms` | `1500` | **the longest the IME freezes after Enter**. At most `2500`: past it some apps lose the draft, so a larger value is capped |
| `max_chars` | `2000` | the longest draft sent, in characters |
| `max_tokens` | `1024` | required by `anthropic` |
| `allow_remote` | `false` | without it, any non-loopback `base_url` is refused |
| `api_key_account` | empty | the Keychain account name for a cloud key; never the key itself |
| `debug_log` | `false` | log to `~/Library/Logs/ime_translate.log` |
| `prompt` | built in | the system prompt for `openai` / `anthropic`; quote it if it contains ` #` |

The cloud backend has its own copy of eight of these keys, with a `cloud_`
prefix: `cloud_backend`, `cloud_base_url`, `cloud_model`, `cloud_prompt`,
`cloud_timeout_ms`, `cloud_max_tokens`, `cloud_api_key_account`, and
`cloud_temperature` (not in the table: the sampling temperature `openai`
sends, default `0.2`). A `cloud_` key you leave out takes the default above,
not the value of its local twin. `allow_remote`, `max_chars` and `debug_log`
have no `cloud_` copy: they apply to both. See "Using a large language
model".

### Using a large language model

Two backends, and a tap of **Right Option** switches between them:
- **Local**: `translate`, the default. Fast, and nothing leaves the
  machine.
- **Cloud**: a large language model you configure yourself. Any
  OpenAI-compatible chat API works through `backend: openai`, and Anthropic's
  API through `backend: anthropic`. Nothing runs locally for this; the IME
  calls the provider's API.

Use the cloud where the network is good, and switch to local where it is not.

**Setting it up**, with GLM (Zhipu) as the example. It was tested on
2026-09-22.

1. **Store the API key in the Keychain.** The service is always
   `ime-translate`. The account name is yours to pick, but it must match
   `cloud_api_key_account` in step 2 exactly. `-w` goes last so that `security`
   prompts for the key, and it stays out of your shell history:

   ```bash
   security add-generic-password -s ime-translate -a zhipu -w
   ```

   - To replace the key, add `-U`.
   - To check it is there, without showing it:
     `security find-generic-password -s ime-translate -a zhipu`.
   - The Keychain Access app works too: a password item named
     `ime-translate`, with the account `zhipu`.

2. **Add the cloud backend** at the end of
   `~/Library/Rime/ime_translate.yaml`. The keys with no prefix stay as they
   are: they are the local backend.

   ```yaml
   allow_remote: true                                    # a non-local server needs this
   cloud_api_key_account: zhipu                          # the Keychain account; never the key itself
   cloud_backend: openai                                 # GLM speaks the OpenAI chat API
   cloud_base_url: https://open.bigmodel.cn/api/paas/v4  # the IME appends /chat/completions
   cloud_model: glm-4-flash-250414
   cloud_timeout_ms: 2500
   ```

   `cloud_backend` and `cloud_base_url` are both required. For another
   provider, change `cloud_base_url` and `cloud_model` to the values it
   documents. For Anthropic's API, use:

   ```yaml
   cloud_backend: anthropic
   cloud_base_url: https://api.anthropic.com/v1
   cloud_model: claude-haiku-4-5
   cloud_max_tokens: 1024
   ```

   Only GLM has been tested with this IME.

3. **Redeploy** (see Configure), then tap Right Option until the notice says
   `云端翻译`. The next Enter shows the model's translation after a `☁`.

   **Upgrading from a single backend?** If your model lines have no `cloud_`
   prefix, the model is your local backend and there is no cloud one:
   a Right Option tap only says `云端未配置`. Add `cloud_` to those lines (keep
   `allow_remote` as it is), and redeploy.

**Switching.**
- **Tap Right Option**: press it alone and release it within half a second.
  It works with nothing typed, in any app, and switches every app at once.
  The choice survives a redeploy or a restart. Left Option does nothing, and
  Option with another key types as usual.
- Right Option held while you click the mouse, and released within half a
  second, also counts as a tap. The notice shows it; tap again to switch back.
- A notice shows `本地翻译` or `云端翻译`. With pinyin still unselected, the
  candidate list may hide it; the `☁` on the next translation still tells.
- A translation from a cloud server shows `☁` in place of `->`, and a cloud
  error shows `☁ ✗ …`.
- There is no automatic fallback. When the cloud fails, Enter commits the
  Chinese, or a Right Option tap then Enter translates it locally.
- With no cloud backend, the notice says `云端未配置`: the translation on
  screen goes, and the backend stays local. A cloud backend you did configure
  but that was refused counts as none. It is refused when `allow_remote` is
  missing, when the URL is not https, or when `cloud_base_url` is missing.
  Turn on `debug_log` to see which: the log names the key.

**Choosing a model.** Pick a fast chat model that does not "think" first. A
reasoning model thinks before it answers, so every Enter freezes for longer,
and the IME cannot turn the thinking off.

**The costs:**
- **Privacy.** Every sentence you translate goes to the provider.
- **Speed.** Each Enter freezes the IME while the request runs, about
  0.5–2 s, and never longer than `cloud_timeout_ms` (default 1500, not the
  local `timeout_ms`). It is capped at 2500: past it, some apps lose the
  draft.
- **Money.** Whatever the provider charges.

**If it shows `☁ ✗ 密钥无效`** (key invalid), the key is missing or wrong.
Most often the Keychain account name differs from `cloud_api_key_account`.

**Back to `translate`.** Tap Right Option until the notice says
`本地翻译`. To remove the cloud for good, delete the `cloud_` lines and
redeploy.

Never put the key itself in `ime_translate.yaml`: the Rime directory is often
synced to GitHub.

### The log

`debug_log: true` writes `~/Library/Logs/ime_translate.log`. While it is on,
the log holds what you type and the translations. Turn it off when you are done,
and delete the file.

## Known limits

- **Focus loss.** Switching app or window with a draft open puts the raw pinyin
  into the application. That is Squirrel's doing, below the IME, and it is
  accepted as a known cost (decision D2). Deal with the draft before you switch
  away: Enter, Shift+Enter or Esc.
- **The starting schema.** A new input box starts in the schema you used last,
  not always in `朙月拼音·简化字` (decision D6: kept). In the translation schema,
  Shift+Enter commits Chinese; `Ctrl+Shift+T` switches back. With a cloud
  backend, an Enter meant as a newline would send the sentence to the vendor
  for translation.
- **No learning.** Committing through the translation schema does not teach
  Rime's user dictionary (risk R13).
- **Translation quality.** `translate` is fast, with a P50 of about 20 ms, but
  it handles URLs poorly: the space around a URL is often lost. See
  [`docs/compat-matrix.md`](docs/compat-matrix.md).

## Uninstall

```bash
R=~/Library/Rime
rm -rf "$R/lua/ime_translate" "$R/lua/ime_translate_processor.lua" "$R/lua/ime_translate_shared.lua"
rm -f "$R/luna_pinyin_translate.schema.yaml" "$R/ime_translate.active"
find "$R" -maxdepth 1 -name 'luna_pinyin_translate.schema.yaml.bak-*' -delete   # backups, if any
sed -i '' '/^ime_translate_processor = require("ime_translate_processor")$/d' "$R/rime.lua"
launchctl bootout "gui/$(id -u)/local.ime-translate.translate-serve"
rm -f ~/Library/LaunchAgents/local.ime-translate.translate-serve.plist
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload
```

Three things are left for you to decide:
- **`$R/default.custom.yaml`.** Delete it only if its first line starts with
  `# managed by ime-translate install.sh`. If it is your own file, remove the
  `schema_list` and `Control+Shift+T` entries you merged into it by hand.
- **`$R/ime_translate.yaml`** holds your settings. Delete it if you want them
  gone.
- **A cloud key**, if you stored one:
  `security delete-generic-password -s ime-translate -a anthropic`.

## Develop

- **Tests:** `scripts/run_tests.sh` runs every headless test (Lua 5.4, no
  dependencies).
- **Progress:** `./scripts/progress.sh status`.
- **Evaluating the backend:** `./scripts/eval.sh`.
- **Conventions and the harness:** [`.claude/rules/core.md`](.claude/rules/core.md).
