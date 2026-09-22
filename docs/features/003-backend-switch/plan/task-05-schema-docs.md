# Task 5: Schema notices, the config template and the README

**Files:**
- Modify: `rime/luna_pinyin_translate.schema.yaml` (the header list, the
  description, `switches`)
- Modify: `rime/ime_translate.yaml` (the template)
- Modify: `README.md` (Use, Configure, "Using a large language model",
  Uninstall)

**Interfaces:**
- Consumes: the notice switch names Task 4 turns on and off.
- Produces: what Task 6 installs and checks.

Design §5.6, "What the user sees", and F29. Squirrel's default
`status_message_type` is `mix`, which shows the **short** label. Without
`abbrev`, the short label is the first character of the state, and `云端翻译`
and `云端未配置` would both show as `云`. So each notice switch gives an
`abbrev` equal to its states, and every style shows the whole text.

- [ ] **Step 1: The schema**

In `rime/luna_pinyin_translate.schema.yaml`, append to the header list:

```yaml
#  10. Three notice switches for Ctrl+Shift+B (feature 003, design §5.6). The
#      processor turns one on and off; Squirrel shows the label of an option
#      turned on. The empty first label keeps each out of the switcher menu,
#      and the abbrev keeps the whole label under status_message_type: mix
#      (upstream F29).
```

Add a line to `schema/description`, after the Shift line:

```yaml
    Ctrl+Shift+B 切换本地/云端翻译（☁ = 云端译文）。
```

Append to `switches`, after `ascii_punct`:

```yaml
  # 10.
  - name: ime_translate_notice_local
    states: [ "", 本地翻译 ]
    abbrev: [ "", 本地翻译 ]
  - name: ime_translate_notice_cloud
    states: [ "", 云端翻译 ]
    abbrev: [ "", 云端翻译 ]
  - name: ime_translate_notice_no_cloud
    states: [ "", 云端未配置 ]
    abbrev: [ "", 云端未配置 ]
```

Check that the names match the processor's `NOTICE` table:

```bash
for n in $(sed -n 's/.*"\(ime_translate_notice_[a-z_]*\)".*/\1/p' rime/lua/ime_translate_processor.lua); do
  grep -q "name: $n\$" rime/luna_pinyin_translate.schema.yaml && echo "ok $n" || echo "MISSING $n"
done
```

Expected: three `ok` lines.

- [ ] **Step 2: The config template**

In `rime/ime_translate.yaml`, the paragraph "One backend at a time: …" becomes:

```yaml
# Two backends, switched with Ctrl+Shift+B inside the translation schema: the
# local slot (the keys with no prefix; translate by default) and the cloud slot
# (the same keys with a cloud_ prefix). The choice is remembered, in
# ime_translate.active next to this file. See README.md, "Using a large
# language model".
```

The `--- local backend …` heading becomes `--- local slot (default:
translate, Apple's on-device NMT) ---`. Add below its `debug_log` line:

```yaml
#                                 # max_chars, debug_log and allow_remote are
#                                 # shared by both slots
```

The whole `--- cloud backend (off by default) ---` block becomes:

```yaml
# --- cloud slot (off until cloud_backend is set) ---
# Every Chinese sentence you translate on the cloud slot goes to a third party.
# That is a known cost, not a defect. Its translations show a ☁.
# allow_remote: true                                    # without this, non-loopback is refused
# cloud_backend: openai                                 # GLM speaks the OpenAI chat API
# cloud_base_url: https://open.bigmodel.cn/api/paas/v4  # remote must be https
# cloud_model: glm-4-flash
# cloud_api_key_account: zhipu                          # Keychain account name, not the key
# cloud_timeout_ms: 2500                                # unset cloud_ keys take the defaults,
#                                                       # not the local slot's values
# For Anthropic: cloud_backend: anthropic, cloud_base_url:
# https://api.anthropic.com/v1, cloud_model: claude-haiku-4-5,
# cloud_max_tokens: 1024
```

- [ ] **Step 3: The README**

- **Use, the key table:** a row after Esc:

  ```markdown
  | Ctrl+Shift+B | switch between the local and the cloud backend | drop the English, switch; Enter translates again with the other one |
  ```

- **"Using a large language model"**. The opening list becomes:

  ```markdown
  Two backends, and `Ctrl+Shift+B` switches between them:
  - **Local**: `translate`, the default. Fast, and nothing leaves the
    machine.
  - **Cloud**: a large language model you configure yourself. Any
    OpenAI-compatible chat API works through `backend: openai`, and
    Anthropic's API through `backend: anthropic`. Nothing runs locally for
    this; the IME calls the provider's API.

  Use the cloud where the network is good, and switch to local where it is
  not.
  ```

- **Step 2 of the setup** uses the `cloud_` keys, and says the local keys stay
  as they are:

  ```yaml
  allow_remote: true                                    # a non-local server needs this
  cloud_api_key_account: zhipu                          # the Keychain account; never the key itself
  cloud_backend: openai                                 # GLM speaks the OpenAI chat API
  cloud_base_url: https://open.bigmodel.cn/api/paas/v4  # the IME appends /chat/completions
  cloud_model: glm-4-flash
  cloud_timeout_ms: 2500
  ```

  and the Anthropic example likewise, with `cloud_backend`, `cloud_base_url`,
  `cloud_model` and `cloud_max_tokens`.
- **Step 3** becomes: redeploy, then press `Ctrl+Shift+B`; `云端翻译` shows,
  and the next Enter shows the model's translation after a `☁`.
- **A new paragraph, "Switching",** after step 3:
  - `Ctrl+Shift+B` switches in every app at once, and the choice survives a
    redeploy or a restart.
  - A notice shows `本地翻译` or `云端翻译`. With pinyin still unselected, the
    candidate list may hide it; the `☁` on the next translation still tells.
  - A translation from a cloud server shows `☁` in place of `->`, and a cloud
    error shows `☁ ✗ …`.
  - There is no automatic fallback. When the cloud fails, Enter commits the
    Chinese, or `Ctrl+Shift+B` then Enter translates it locally.
  - With no cloud slot configured, the notice says `云端未配置` and nothing
    changes.
- **"Back to `translate`"** becomes: press `Ctrl+Shift+B` until the notice
  says `本地翻译`. To remove the cloud for good, delete the `cloud_` lines and
  redeploy.
- **Configure:** below the key table:

  ```markdown
  Every key from `backend` to `prompt`, and `api_key_account`, has a `cloud_`
  twin for the cloud backend. `allow_remote`, `max_chars` and `debug_log` are
  shared. See "Using a large language model".
  ```

- **Uninstall:** add `rm -f "$R/ime_translate.active"` after the schema line.

- [ ] **Step 4: Check**

```bash
scripts/run_tests.sh
.claude/hooks/tests/run-hook-tests.sh >/dev/null && echo hooks ok
grep -c "cloud_" README.md rime/ime_translate.yaml
```

Expected: every file PASS, `hooks ok`, and a non-zero count for both files.

- [ ] **Step 5: Commit**

```bash
git add rime/luna_pinyin_translate.schema.yaml rime/ime_translate.yaml README.md
git commit -m "feat: backend-switch notices; README and template for two slots"
```
