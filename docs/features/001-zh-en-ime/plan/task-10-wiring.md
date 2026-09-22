# Task 10: Schema wiring + installer + LaunchAgent + first real-machine smoke

> **Revised before start (2026-09-21).** This is the version that is built.
> What changed and why is in [decisions.md](../../../design/decisions.md),
> "Task 10 revised before start"; in short:
>
> - D4: `translate` is the only local backend. There is no apfel plist, and no
>   `:11434`.
> - D1: the schema inserts one lua component, the processor. The translation
>   shows in the prompt after the draft (design §6.4).
> - The user's daily schema is `luna_pinyin_simp`, so the translation schema
>   pairs with it.
>   - `Ctrl+Shift+T` switches between the two.
>   - The script switch is `luna_pinyin_simp`'s `zh_simp`, reset to
>     Simplified as it is there (D5, amended by the user).
> - The schema is a full copy of the stock `luna_pinyin.schema.yaml`, with the
>   changes marked. That is the form spike Task 1 built and measured.
>   `__include` with sibling keys was never measured.
> - `default.custom.yaml` appends to `schema_list` rather than replacing it.
> - Lua components need a `rime.lua` binding; the spike found this the hard way.
> - `install.sh` no longer parses the config; it always installs the
>   `translate` service.
> - The smoke list grows from 16 checks to 28 rows, each marked `gate` or
>   `record`. It picks up every open item from the reviews of Tasks 5-9.
> - The user accepted `Control+g` / `Control+bracketleft` knowingly (Task 8
>   review, yellow 4); row 25 records it.
>
> Earlier text lives in git history.

**Files:**
- Create: `rime/luna_pinyin_translate.schema.yaml`, `rime/default.custom.yaml`,
  `rime/ime_translate.yaml`
- Create: `launchd/local.ime-translate.translate-serve.plist`
- Create: `scripts/install.sh`

**Interfaces:**
- Consumes:
  - Task 9's component module name, `ime_translate_processor`
  - Task 5's config file format
  - the spike report's S2 fallback, S5 and `rime.lua` findings
- Produces: a working translation IME schema and an idempotent installer

**Step 6 needs the real machine.** By the user's decision, the agent drives it
and records what it reads back. The user watches the rows marked 👁. Each row's
record says how it was observed.

- [ ] **Step 1: The translation schema**

`rime/luna_pinyin_translate.schema.yaml` is a copy of the stock
`luna_pinyin.schema.yaml` from Squirrel 1.1.2's `SharedSupport`, with the
seven numbered changes below. Everything not marked is stock.

```yaml
# Chinese->English translation schema, paired with luna_pinyin_simp. A copy of
# the stock luna_pinyin.schema.yaml -- the form spike Task 1 built and measured
# -- with these changes, marked where they are made:
#   1. fluid_editor replaces express_editor: no auto-commit, so selection and
#      punctuation stay in the composition and the IME owns the whole draft.
#   2. One lua component, the processor, comes first so it sees Enter ahead of
#      the native editor. It shows the translation in the prompt (decision D1).
#   3. The script switch is luna_pinyin_simp's zh_simp, reset to Simplified as
#      it is there (decision D5, amended 2026-09-21).
#   4. The committing punctuation marks are plain strings (spike S2 fallback).
#   5. Control+Shift+T goes back to luna_pinyin_simp.
#   6. ascii_punct resets to Chinese punctuation, which 4. relies on.
#   7. user_dict is spelled out, and the customization hook is this schema's.
schema:
  schema_id: luna_pinyin_translate
  name: 朙月拼音·译
  version: "1.0"
  author:
    - ime-translate
  description: |
    打中文，回车翻译，再回车上屏英文。
    Shift+回车 = 不翻译直接上中文。Esc = 弃译文继续编辑。
    Ctrl+Shift+T 切回朙月拼音·简化字。
  dependencies:
    - stroke

switches:
  - name: ascii_mode
    reset: 0
    states: [ 中文, 西文 ]
  - name: full_shape
    states: [ 半角, 全角 ]
  # 3. Simplified whenever the schema loads. Ctrl+Shift+4 or the switcher menu
  #    changes it for the session; that is not saved, because zh_simp is not in
  #    default.yaml's switcher/save_options.
  - name: zh_simp
    reset: 1
    states: [ 漢字, 汉字 ]
  - name: ascii_punct
    reset: 0                                  # 6.
    states: [ 。，, ．， ]

engine:
  processors:
    - lua_processor@ime_translate_processor   # 2.
    - ascii_composer
    - recognizer
    - key_binder
    - speller
    - punctuator
    - selector
    - navigator
    - fluid_editor                            # 1.
  segmentors:
    - ascii_segmentor
    - matcher
    - abc_segmentor
    - punct_segmentor
    - fallback_segmentor
  translators:
    - punct_translator
    - table_translator@custom_phrase
    - reverse_lookup_translator
    - script_translator
  filters:
    - simplifier
    - uniquifier

speller:
  alphabet: zyxwvutsrqponmlkjihgfedcba
  delimiter: " '"
  algebra:
    __patch:
      - pinyin:/abbreviation
      - pinyin:/spelling_correction
      - pinyin:/key_correction

translator:
  dictionary: luna_pinyin
  user_dict: luna_pinyin      # 7. shared with luna_pinyin and luna_pinyin_simp
  preedit_format:
    - xform/([nl])v/$1ü/
    - xform/([nl])ue/$1üe/
    - xform/([jqxy])v/$1u/

custom_phrase:
  dictionary: ""
  user_dict: custom_phrase
  db_class: stabledb
  enable_completion: false
  enable_sentence: false
  initial_quality: 1

reverse_lookup:
  dictionary: stroke
  enable_completion: true
  prefix: "`"
  suffix: "'"
  tips: 〔筆畫〕
  preedit_format:
    - xlit/hspnz/一丨丿丶乙/
  comment_format:
    - xform/([nl])v/$1ü/

simplifier:
  option_name: zh_simp        # 3., as in luna_pinyin_simp

punctuator:
  import_preset: symbols
  # 4. Plain strings confirm the selection, which under fluid_editor only
  #    advances the composition; the preset's { commit: ... } forms call
  #    Context::Commit() and put the whole draft into the application.
  half_shape:
    ',' : '，'
    '.' : '。'
    '?' : '？'
    '!' : '！'
    ';' : '；'
    ':' : '：'
    '^' : '……'

# import_preset MUST stay, and this section must stay the only key_binder: a
# second top-level key_binder silently replaces the first (spike, Step 5).
# These bindings are appended to the preset's.
key_binder:
  import_preset: default
  bindings:
    # 5. After the preset's forward binding (default.custom.yaml), so it is
    #    the one that applies here (measured in the spike).
    - { when: always, accept: "Control+Shift+T", select: luna_pinyin_simp }
    # as in luna_pinyin_simp: the script toggle follows zh_simp
    - { when: always, accept: Control+Shift+4, toggle: zh_simp }
    - { when: always, accept: Control+Shift+dollar, toggle: zh_simp }

recognizer:
  import_preset: default
  patterns:
    punct: '^/([0-9]0?|[A-Za-z]+)$'
    reverse_lookup: "`[a-z]*'?$"

__patch:
  - grammar:/hant?
  # 7. the user's own customization of this schema, by Rime's convention
  - luna_pinyin_translate.custom:/patch?
```

(The schema's `name` and `description` stay Chinese: they are shown in the macOS
input menu to a Chinese-reading user.)

Before copying, check that the stock schema has not moved on. If this diff
shows anything beyond the seven marked changes, carry the stock change over and
note it in the task report:

```bash
diff <(sed 's/#.*//' "/Library/Input Methods/Squirrel.app/Contents/SharedSupport/luna_pinyin.schema.yaml") \
     <(sed 's/#.*//' rime/luna_pinyin_translate.schema.yaml)
```

- [ ] **Step 2: Schema list and the forward hotkey**

`rime/default.custom.yaml`:

```yaml
# managed by ime-translate install.sh -- see scripts/install.sh before editing
# Append the translation schema to the schema list (the stock list stays), and
# bind Ctrl+Shift+T to switch into it. The default preset is imported by every
# stock schema, so the binding works from any of them. The reverse binding
# lives in luna_pinyin_translate.schema.yaml's own key_binder.
patch:
  schema_list/+:
    - schema: luna_pinyin_translate
  key_binder/bindings/+:
    - { when: always, accept: "Control+Shift+T", select: luna_pinyin_translate }
```

`key_binder/bindings/+` is the form the spike measured. `schema_list/+` uses the
same list-append mechanism, but it was **not measured**. Step 6 row 16 checks
that the list holds both the stock schemas and this one.

- [ ] **Step 3: User config defaults**

`rime/ime_translate.yaml`:

```yaml
# ime_translate configuration (flat key: value, # comments)
#
# WARNING: never put an API key in this file. It lives in the Rime user
#   directory, which is rescanned wholesale on "Redeploy" and is frequently
#   pushed to GitHub as config sync.
#   Store the key in the Keychain instead:
#     security add-generic-password -s ime-translate -a <account> -w <your-key>
#   and put only the account name here.
#
# Changes take effect after Squirrel restarts:
#   "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --quit
#
# --- local backend (default: translate, Apple's on-device NMT) ---
# backend: libretranslate         # openai | libretranslate | anthropic
# base_url: http://127.0.0.1:8989
#
# timeout_ms: 1500                # WARNING: this number is the upper bound on
#                                 # how long the IME freezes after you press
#                                 # Enter. Past about 2500 some apps lose the
#                                 # draft (spike S13).
# max_chars: 2000                 # characters, not bytes
# debug_log: false                # log goes to ~/Library/Logs/ime_translate.log
#
# A value containing " #" must be quoted, or the rest is read as a comment:
# prompt: "Translate ... #tags stay as they are"
#
# --- cloud backend (off by default) ---
# Turning cloud on means every Chinese sentence you translate goes to a third
# party. That is a known cost, not a defect.
# allow_remote: true                      # without this, non-loopback is refused
# api_key_account: anthropic              # Keychain account name, not the key
# base_url: https://api.anthropic.com/v1  # remote must be https
# backend: anthropic
# model: claude-haiku-4-5
# max_tokens: 1024                        # required by anthropic
```

- [ ] **Step 4: The LaunchAgent**

`launchd/local.ime-translate.translate-serve.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.ime-translate.translate-serve</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/translate</string>
    <string>--serve</string>
    <string>--port</string>
    <string>8989</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <!-- translate --serve ignores SIGTERM (measured during Task 6): without this
       launchd waits its default 20 s before SIGKILL on every bootout -->
  <key>ExitTimeOut</key><integer>2</integer>
  <key>StandardOutPath</key><string>/tmp/translate-serve.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/translate-serve.err.log</string>
</dict>
</plist>
```

> The zh→en model is already downloaded on this machine (spike S8). A new
> machine needs it once: System Settings → General → Language & Region →
> Translation Languages. `install.sh` cannot automate that.
>
> **Not measured:** whether `Translation.framework` works from a LaunchAgent's
> background context (design §12, R8). The spike ran `translate --serve` from a
> login shell. Step 6's first command checks it. If the service answers from a
> shell but not under launchd, move it to a login item in the user's Aqua
> session.

- [ ] **Step 5: The installer**

`scripts/install.sh`:

```bash
#!/bin/bash
# Idempotent install: Lua, schema and config into the Rime user directory, the
# local translation service into launchd. A second run changes nothing, and the
# user's own files are never overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."
RIME="$HOME/Library/Rime"
AGENTS="$HOME/Library/LaunchAgents"
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
TRANSLATE=/opt/homebrew/bin/translate   # must match the plist
PLIST=local.ime-translate.translate-serve
STAMP=$(date +%Y%m%d-%H%M%S)
lua_changed=0

[ -x "$SQUIRREL" ] || { echo "Squirrel not found at $SQUIRREL" >&2; exit 1; }
[ -x "$TRANSLATE" ] || { echo "translate not found at $TRANSLATE (brew install translate?)" >&2; exit 1; }
mkdir -p "$RIME/lua/ime_translate" "$AGENTS"

# put SRC DEST [backup]: copy when the content differs, keeping a differing DEST
# first when asked. Returns 0 if it copied, 1 if DEST was already identical.
put() {
  local src=$1 dest=$2 backup=${3:-}
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then return 1; fi
  if [ -n "$backup" ] && [ -f "$dest" ]; then cp "$dest" "$dest.bak-$STAMP"; fi
  cp "$src" "$dest"
  echo "installed $dest"
}

# Lua. The ime_translate/ subdirectory MUST be preserved:
# require("ime_translate.state") looks for lua/ime_translate/state.lua.
for f in rime/lua/ime_translate/*.lua; do
  put "$f" "$RIME/lua/ime_translate/$(basename "$f")" && lua_changed=1 || true
done
for f in rime/lua/ime_translate_*.lua; do
  put "$f" "$RIME/lua/$(basename "$f")" && lua_changed=1 || true
done

# rime.lua: librime-lua resolves lua_processor@ime_translate_processor to a Lua
# global of that name defined here. Without it the component is created with
# no error and never runs (spike report, "Deviations from the plan").
BIND='ime_translate_processor = require("ime_translate_processor")'
touch "$RIME/rime.lua"
if ! grep -qxF "$BIND" "$RIME/rime.lua"; then
  if [ -s "$RIME/rime.lua" ] && [ -n "$(tail -c1 "$RIME/rime.lua")" ]; then
    echo >> "$RIME/rime.lua"
  fi
  printf '%s\n' "$BIND" >> "$RIME/rime.lua"
  echo "bound ime_translate_processor in $RIME/rime.lua"
  lua_changed=1
fi

# The schema is this project's: update it, keeping a differing old copy.
put rime/luna_pinyin_translate.schema.yaml "$RIME/luna_pinyin_translate.schema.yaml" backup || true

# default.custom.yaml may be the user's own. Replace it only if it carries this
# project's marker; otherwise leave it and say what to merge.
MARK='# managed by ime-translate install.sh'
if [ ! -f "$RIME/default.custom.yaml" ] || grep -qF "$MARK" "$RIME/default.custom.yaml"; then
  put rime/default.custom.yaml "$RIME/default.custom.yaml" backup || true
else
  echo "NOT touched: $RIME/default.custom.yaml is not ours. Merge these into its patch: by hand:"
  sed -n '/^patch:/,$p' rime/default.custom.yaml | sed 1d
fi

# User config: laid down only when missing.
if [ ! -f "$RIME/ime_translate.yaml" ]; then
  cp rime/ime_translate.yaml "$RIME/ime_translate.yaml"
  echo "wrote default config to $RIME/ime_translate.yaml"
fi

# The local backend. Installed whatever the config says: it is the default, and
# idle when a cloud backend is configured.
DOMAIN="gui/$(id -u)"
if put "launchd/$PLIST.plist" "$AGENTS/$PLIST.plist"; then
  launchctl bootout "$DOMAIN/$PLIST" 2>/dev/null || true
  for _ in $(seq 50); do
    launchctl print "$DOMAIN/$PLIST" >/dev/null 2>&1 || break
    sleep 0.2
  done
fi
if ! launchctl print "$DOMAIN/$PLIST" >/dev/null 2>&1; then
  launchctl bootstrap "$DOMAIN" "$AGENTS/$PLIST.plist"
  echo "started $PLIST"
fi

"$SQUIRREL" --reload
echo "Squirrel: redeployed"
if [ "$lua_changed" = 1 ]; then
  cat <<EOF
Lua changed: Squirrel keeps the old modules until it restarts. With no draft
open anywhere (an open draft is committed as raw pinyin), run:
  "$SQUIRREL" --quit
It relaunches on the next key.
EOF
fi

cat <<'EOF'

Install complete. If this is a new machine:
  1. System Settings -> Keyboard -> Input Sources: add Squirrel (one-off; if
     it is missing, log out and in once -- Squirrel installed mid-session is
     not listed)
  2. Download the Chinese -> English translation model (see the plist note)
Then Ctrl+Shift+T switches between luna_pinyin_simp and the translation schema.
EOF
```

```bash
chmod +x scripts/install.sh
```

- [ ] **Step 6: Install it and run the real-machine smoke checks**

```bash
./scripts/install.sh
./scripts/install.sh      # idempotency: the second run prints no "installed" line
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --quit
# The backend under launchd (R8):
curl -sS --max-time 3 -X POST http://127.0.0.1:8989/translate \
  -H 'Content-Type: application/json' \
  -d '{"q":"收到","source":"zh","target":"en","format":"text"}'; echo
```

Pass criterion for the curl: a `translatedText` answer.

For rows 13 and 14, a stand-in backend is needed. Point `base_url` at it in
`~/Library/Rime/ime_translate.yaml`, then restart Squirrel with `--quit`.
Restore the config and restart again afterwards.

```bash
cat > /tmp/ime-stub.py <<'PY'
# A stand-in libretranslate: answers every POST after DELAY seconds with TEXT.
import http.server, json, sys, time
PORT, DELAY, TEXT = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        time.sleep(DELAY)
        body = json.dumps({"translatedText": TEXT}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY
python3 /tmp/ime-stub.py 18990 1.2 "Slow answer" &                # row 13
python3 /tmp/ime-stub.py 18990 0 "$(printf 'Line one\nLine two')" & # row 14
```

**How to read the table:**
- "State A" means every segment is confirmed (space after each word).
- "State B" means the last pinyin segment is left open.
- **gate** rows must pass.
- **record** rows pass once the observation is written down, as S12 and S14
  did in the spike.
- 👁 means the user watches.

| # | Action | Expected | Kind |
|---|---|---|---|
| | **A. The loop (TextEdit)** | | |
| 1 | Type `jintianyoudianlei`, press space | Preedit only (underlined); nothing committed | gate |
| 2 | Then type `buguo`, press `2` | The draft keeps growing, uncommitted | gate |
| 3 | Type `,` | The comma joins the draft | gate |
| 4 | Press Enter | A brief freeze, then the preedit reads draft, then `  -> `, then English; nothing committed | gate 👁 |
| 5 | Press Enter again | The English commits at once; no Chinese residue | gate 👁 |
| 6 | Another sentence, Enter, Enter | It translates and commits too | gate |
| | **B. Leaving the result phase** | | |
| 7 | Prompt showing, press `a` | The prompt goes; `a` joins the draft as pinyin | gate |
| 8 | State B, prompt showing, press `2` | The 2nd Chinese candidate is selected; the prompt goes | gate |
| 9 | Prompt showing, BackSpace | The prompt goes; the draft steps back one | gate |
| 10 | Prompt showing, Esc | The prompt goes; the draft stays; typing continues | gate |
| 11 | Sentence, Shift+Enter | The Chinese draft commits with no freeze. With `debug_log: true`, the log has no `translate` line | gate |
| | **C. Errors and the stall** | | |
| 12 | `launchctl bootout gui/$(id -u)/local.ime-translate.translate-serve`, then sentence, Enter | Preedit ends with `  ✗ 翻译服务未启动`. Enter again commits the Chinese. Bootstrap the service back afterwards | gate |
| 13 | Stub, 1.2 s. Sentence, Enter, then type `abcde` during the freeze | Nothing reaches the app early. Afterwards all five letters are in the draft, in order, and the prompt is gone | gate |
| 14 | Stub, `Line one` newline `Line two`. Sentence, Enter, Enter | Record what the prompt shows and what commits (Task 7 review) | record |
| | **D. Sessions and schemas** | | |
| 15 | TextEdit: sentence, Enter (prompt showing), then switch to Notes. In Notes: a sentence, Enter, Enter | Notes shows and commits its own translation, never TextEdit's. Record what landed in TextEdit (spike S12: raw pinyin, D2) | gate + record |
| 16 | Half a draft, Ctrl+Shift+T, type a word, space; then Ctrl+Shift+T again. Then open a new TextEdit document and type in it | `luna_pinyin_simp` behaves natively (space commits) and back again. The translation schema's draft is Simplified, including in a session that starts in it. The menu (Ctrl+backquote) lists the stock schemas plus this one | gate |
| | **E. Keys and edits found by review** | | |
| 17 | Keypad Enter, if a keyboard with a keypad is at hand | Same as rows 4-5. With no keypad: unverified | gate if possible |
| 18 | Type `jintiantianqihenhao`, no selection, Left once, Shift+Enter; then Shift+Enter | The first press commits nothing and moves the caret to the end. The second commits the whole draft, `好` included | gate |
| 19 | Same setup, Left once, then Enter, Enter, Enter | Caret to the end; then the whole draft translates; then it commits | gate |
| 20 | Left into the pinyin, Down to highlight a non-default candidate, Enter | Record what the draft shows (expected by source reading: the highlight falls back to the default) | record |
| 21 | State B, prompt showing: scroll the candidate window with the mouse wheel, then Esc | The draft stays | gate 👁 |
| 22 | State B, prompt showing: click the highlighted candidate, then Enter | Record whether the prompt vanishes, and what commits. English committed while it was not on screen fails the row, and it is fixed before this task closes (Task 9 review, round 2) | gate 👁 |
| 23 | State B, prompt showing: click the 3rd candidate, then Enter | The old English is never committed: the new draft translates | gate 👁 |
| 24 | Prompt showing, Shift+Esc | Record it. Expected by source reading: the draft is wiped, as by Esc in idle | record |
| 25 | Prompt showing, Control+g | Record it. Expected: the draft is wiped (accepted by the user) | record |
| 26 | A draft open, press Caps Lock | Record it (spike: `Caps_Lock: clear`, a source reading) | record |
| | **F. WeChat, file transfer chat** | | |
| 27 | Sentence, Enter (prompt), Enter | The English is in the input box and **not sent**; only a separate Enter sends | gate 👁 |
| 28 | Sentence, Enter (prompt), Esc | The draft stays in the input box | gate |

If a gate row fails, go back to the task that owns the behaviour and fix it
there; do not patch around it here. Record every row in the task report with
how it was observed: agent readback, agent screenshot, or the user.

- [ ] **Step 7: Commit**

```bash
git add rime/luna_pinyin_translate.schema.yaml rime/default.custom.yaml \
        rime/ime_translate.yaml launchd/ scripts/install.sh
git commit -m "feat: schema wiring, installer and LaunchAgent"
```
