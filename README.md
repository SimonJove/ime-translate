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
| `timeout_ms` | `1500` | **the longest the IME freezes after Enter**; past about 2500 some apps lose the draft |
| `max_chars` | `2000` | the longest draft sent, in characters |
| `max_tokens` | `1024` | required by `anthropic` |
| `allow_remote` | `false` | without it, any non-loopback `base_url` is refused |
| `api_key_account` | empty | the Keychain account name for a cloud key; never the key itself |
| `debug_log` | `false` | log to `~/Library/Logs/ime_translate.log` |
| `prompt` | built in | the system prompt for `openai` / `anthropic`; quote it if it contains ` #` |

### Using a large language model

One translation backend at a time:
- **`translate`**, the default: local, fast, nothing leaves the machine.
- **A large language model you configure yourself.** Any OpenAI-compatible
  chat API works through `backend: openai`, and Anthropic's API through
  `backend: anthropic`. Nothing runs locally for this; the IME calls the
  provider's API.

**Setting it up**, with GLM (Zhipu) as the example. It was tested on
2026-09-22.

1. **Store the API key in the Keychain.** The service is always
   `ime-translate`. The account name is yours to pick, but it must match
   `api_key_account` in step 2 exactly. `-w` goes last so that `security`
   prompts for the key, and it stays out of your shell history:

   ```bash
   security add-generic-password -s ime-translate -a zhipu -w
   ```

   - To replace the key, add `-U`.
   - To check it is there, without showing it:
     `security find-generic-password -s ime-translate -a zhipu`.
   - The Keychain Access app works too: a password item named
     `ime-translate`, with the account `zhipu`.

2. **Add the backend** at the end of `~/Library/Rime/ime_translate.yaml`:

   ```yaml
   allow_remote: true                              # a non-local server needs this
   api_key_account: zhipu                          # the Keychain account; never the key itself
   backend: openai                                 # GLM speaks the OpenAI chat API
   base_url: https://open.bigmodel.cn/api/paas/v4  # the IME appends /chat/completions
   model: glm-4-flash
   timeout_ms: 2500
   ```

   For another provider, change `base_url` and `model` to the values it
   documents. For Anthropic's API, use:

   ```yaml
   backend: anthropic
   base_url: https://api.anthropic.com/v1
   model: claude-haiku-4-5
   max_tokens: 1024
   ```

   Only GLM has been tested with this IME.

3. **Redeploy** (see Configure). The next Enter shows the model's translation
   after the draft.

**Choosing a model.** Pick a fast chat model that does not "think" first. A
reasoning model thinks before it answers, so every Enter freezes for longer,
and the IME cannot turn the thinking off.

**The costs:**
- **Privacy.** Every sentence you translate goes to the provider.
- **Speed.** Each Enter freezes the IME while the request runs, about
  0.5–2 s, and never longer than `timeout_ms`. Keep that at 2500 or below:
  past it, some apps lose the draft.
- **Money.** Whatever the provider charges.

**If it shows `✗ 密钥无效`** (key invalid), the key is missing or wrong. Most
often the Keychain account name differs from `api_key_account`.

**Back to `translate`.** Delete those lines, or put `#` in front of them, and
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
rm -f "$R/luna_pinyin_translate.schema.yaml"
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
