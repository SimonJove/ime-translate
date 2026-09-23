#!/bin/bash
# Health check for an installed ime-translate: one pass over everything that
# makes an Enter translate, with what to do for each problem. Read-only: it
# changes no file, no setting and no service.
#
#   ./scripts/doctor.sh           everything local; nothing leaves the machine
#   ./scripts/doctor.sh --cloud   also sends one test sentence to the cloud slot
#
# It prints key names, URLs and Keychain account names, never a key, a prompt
# or anything you typed. Exit status: 1 if any check FAILed, else 0.
set -u
cd "$(dirname "$0")/.."
RIME="${IME_TRANSLATE_RIME_DIR:-$HOME/Library/Rime}"
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
PLIST=local.ime-translate.translate-serve
LOG="$HOME/Library/Logs/ime_translate.log"
cloud_probe=0
case "${1:-}" in
  "") ;;
  --cloud) cloud_probe=1 ;;
  *) echo "usage: $0 [--cloud]" >&2; exit 2 ;;
esac

fails=0 warns=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; [ -n "${2:-}" ] && printf '        -> %s\n' "$2"; warns=$((warns + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        -> %s\n' "$2"; fails=$((fails + 1)); }
section() { printf '\n%s\n' "$1"; }

section "Squirrel"
if [ -x "$SQUIRREL" ]; then ok "installed"
else fail "not found at $SQUIRREL" "brew install --cask squirrel"; fi
# A warning, not a failure: this is macOS's preference file, read from the
# outside, and what it records is not a documented interface.
if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null \
     | grep -q 'im.rime.inputmethod.Squirrel'; then
  ok "enabled as an input source"
else
  warn "not listed among the enabled input sources" \
       "if the input menu lacks Squirrel: System Settings -> Keyboard -> Input Sources, add it"
fi

section "Installed files"
# The installed copy must be the repository's: a stale one runs old behaviour
# with no sign of it.
stale=""
for f in rime/lua/ime_translate/*.lua; do
  cmp -s "$f" "$RIME/lua/ime_translate/$(basename "$f")" || stale="$stale $(basename "$f")"
done
for f in rime/lua/ime_translate_*.lua rime/luna_pinyin_translate.schema.yaml; do
  case "$f" in *.lua) dest="$RIME/lua/$(basename "$f")" ;; *) dest="$RIME/$(basename "$f")" ;; esac
  cmp -s "$f" "$dest" || stale="$stale $(basename "$f")"
done
if [ -z "$stale" ]; then ok "Lua and schema match this checkout"
else warn "differs from this checkout:$stale" "./scripts/install.sh"; fi
if grep -qx 'ime_translate_processor = require("ime_translate_processor")' "$RIME/rime.lua" 2>/dev/null; then
  ok "processor bound in rime.lua"
else
  fail "processor not bound in $RIME/rime.lua: Enter does nothing special" "./scripts/install.sh"
fi
if grep -q 'luna_pinyin_translate' "$RIME/default.custom.yaml" 2>/dev/null; then
  ok "translation schema in the schema list"
else
  fail "luna_pinyin_translate missing from $RIME/default.custom.yaml" \
       "./scripts/install.sh, or merge its schema_list entry by hand"
fi

section "Local backend (translate)"
if launchctl print "gui/$(id -u)/$PLIST" >/dev/null 2>&1; then ok "LaunchAgent $PLIST loaded"
else fail "LaunchAgent $PLIST not loaded" "./scripts/install.sh"; fi
# A fixed two-character test sentence, JSON-escaped so this file stays English.
# Loopback only, with no proxy: nothing leaves the machine.
body=$(curl -q -sS --noproxy '*' --max-time 3 -w '\n%{http_code}' \
         -H 'Content-Type: application/json' \
         -d '{"q": "\u4f60\u597d", "source": "zh", "target": "en", "format": "text"}' \
         http://127.0.0.1:8989/translate 2>&1)
code=${body##*$'\n'}
if [ "$code" = 200 ] && printf '%s' "$body" | grep -q '"translatedText" *: *"[^"]'; then
  ok "answers on 127.0.0.1:8989"
elif [ "$code" = 000 ]; then
  fail "no answer on 127.0.0.1:8989" "launchctl kickstart -k gui/$(id -u)/$PLIST; see /tmp/translate-serve.err.log"
else
  fail "answered HTTP $code without a translation" \
       "download Chinese -> English: System Settings -> General -> Language & Region -> Translation Languages"
fi

section "Config ($RIME/ime_translate.yaml)"
# The IME's own parser, from this checkout, so the verdict is the one the IME
# reaches. Lines out: "M" (no file), "W <warning>", "S <slot> <field> <value>",
# "D <debug_log>", "A <remembered slot>".
report=$(IME_CFG="$RIME/ime_translate.yaml" IME_ACTIVE="$RIME/ime_translate.active" \
  lua -e '
package.path = "rime/lua/?.lua;" .. package.path
local config = require("ime_translate.config")
local f = io.open(os.getenv("IME_CFG"), "r")
if not f then print("M") end
local s, warnings = config.load(function() return f and f:read("*a") or nil end)
if f then f:close() end
for _, w in ipairs(warnings) do print("W " .. w) end
local function slot(name, t)
  for _, k in ipairs({ "backend", "base_url", "model", "timeout_ms", "api_key_account" }) do
    print(("S %s %s %s"):format(name, k, tostring(t[k])))
  end
end
slot("local", s)
if s.cloud then slot("cloud", s.cloud) end
print("D " .. tostring(s.debug_log))
local a = io.open(os.getenv("IME_ACTIVE"), "r")
print("A " .. ((a and a:read("*l")) or "local"))
if a then a:close() end
' 2>&1) || { fail "could not run the config parser: $report" "is lua 5.4 installed?"; report=""; }

if printf '%s\n' "$report" | grep -qx M; then
  warn "no config file: every key takes its default" "./scripts/install.sh lays one down"
fi
nw=0
while IFS= read -r line; do
  case "$line" in "W "*) warn "${line#W }"; nw=$((nw + 1)) ;; esac
done <<< "$report"
[ "$nw" = 0 ] && [ -n "$report" ] && ok "no warnings"
field() { printf '%s\n' "$report" | sed -n "s/^S $1 $2 //p"; }
has_cloud=0
printf '%s\n' "$report" | grep -q '^S cloud ' && has_cloud=1
ok "local slot: $(field local backend) at $(field local base_url), timeout $(field local timeout_ms) ms"
if [ "$has_cloud" = 1 ]; then
  ok "cloud slot: $(field cloud backend) at $(field cloud base_url), model $(field cloud model), timeout $(field cloud timeout_ms) ms"
else
  ok "no cloud slot: a Right Option tap says it is not configured"
fi
active=$(printf '%s\n' "$report" | sed -n 's/^A //p')
[ "$active" = cloud ] && [ "$has_cloud" = 0 ] && active="local (cloud remembered, but no cloud slot)"
ok "active backend: ${active:-local}"

section "Keychain (service ime-translate)"
# Existence only: without -w, security prints no secret.
checked=0
for s in local cloud; do
  acct=$(field "$s" api_key_account)
  [ -n "$acct" ] || continue
  checked=1
  if security find-generic-password -s ime-translate -a "$acct" >/dev/null 2>&1; then
    ok "$s slot: key for account '$acct' present"
  else
    fail "$s slot: no key for account '$acct' (shows as key invalid)" \
         "security add-generic-password -s ime-translate -a '$acct' -w"
  fi
done
[ "$checked" = 0 ] && ok "no slot uses a key"

section "Privacy"
if [ "$(printf '%s\n' "$report" | sed -n 's/^D //p')" = true ]; then
  warn "debug_log is on: the log records what you type" "set debug_log: false, redeploy, delete $LOG"
else
  ok "debug_log off"
fi
if [ -e "$LOG" ]; then warn "$LOG exists and may hold typed text" "rm '$LOG'"
else ok "no log file"; fi

if [ "$cloud_probe" = 1 ]; then
  section "Cloud probe (sends one test sentence to the provider)"
  if [ "$has_cloud" = 0 ]; then
    warn "no cloud slot to probe"
  else
    # The IME's real path: the Keychain read, the adapter, curl with the
    # slot's timeout. Prints an error code, never the key.
    probe=$(IME_CFG="$RIME/ime_translate.yaml" lua -e '
package.path = "rime/lua/?.lua;" .. package.path
local shared = require("ime_translate_shared")
local backend = require("ime_translate.backend")
shared.config_path = os.getenv("IME_CFG")
shared.active_path = "/dev/null"
local S = shared.ensure()
local ok, out = backend.translate(S.settings.cloud, "\u{4f60}\u{597d}", backend.real_runner, S.cloud_key)
print(ok and "OK" or ("ERR " .. out))
' 2>&1)
    case "$probe" in
      OK) ok "the cloud slot translated the test sentence" ;;
      "ERR auth_error") fail "auth_error: the provider refused the key" "check the Keychain account name and the key" ;;
      "ERR timeout") fail "timeout: no answer within cloud_timeout_ms" "a slow network or model; tap Right Option for local" ;;
      "ERR rate_limited") fail "rate_limited: HTTP 429" "wait, or pick another model" ;;
      "ERR conn_refused") fail "conn_refused: cannot reach cloud_base_url" "check the URL and the proxy" ;;
      *) fail "${probe:-no output}" "check cloud_base_url and cloud_model against the provider's docs" ;;
    esac
  fi
fi

printf '\n%d failed, %d warnings\n' "$fails" "$warns"
[ "$fails" = 0 ]
