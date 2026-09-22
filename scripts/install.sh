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
status=0
# Set when a run fails after new Lua is in place, so that the next successful
# run still reports that the Lua changed.
PENDING="$RIME/.ime_translate_restart_pending"

# The Lua notice runs on every exit, early ones included: once new Lua is in
# place, a failure before the redeploy at the end must not hide that Squirrel
# still runs the old modules (Task 10 review, round 2). A redeploy builds a
# fresh Lua state, so the successful run needs no restart (upstream F28).
lua_notice() {
  local rc=$?
  if [ "$rc" != 0 ]; then
    if [ "$lua_changed" = 1 ] || [ -f "$PENDING" ]; then
      touch "$PENDING" 2>/dev/null || true
      echo "Some Lua files are already new, but the install did not finish. Fix the"
      echo "error above and run install.sh again: its redeploy loads the new Lua."
    fi
  elif [ "$lua_changed" = 1 ] || [ -f "$PENDING" ]; then
    rm -f "$PENDING"
    echo "Lua changed: the redeploy above loaded it. No restart is needed."
  fi
}
trap lua_notice EXIT

[ -x "$SQUIRREL" ] || { echo "Squirrel not found at $SQUIRREL" >&2; exit 1; }
[ -x "$TRANSLATE" ] || { echo "translate not found at $TRANSLATE (brew install translate?)" >&2; exit 1; }
mkdir -p "$RIME/lua/ime_translate" "$AGENTS"

# put SRC DEST [backup]: copy when the content differs, keeping a differing DEST
# first when asked. Returns 0 if it copied, 1 if DEST was already identical.
# A failed copy exits the script: every caller sits in &&, || or if, where
# set -e is suspended for the whole function (Task 10 review).
put() {
  local src=$1 dest=$2 backup=${3:-}
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then return 1; fi
  if [ -n "$backup" ] && [ -f "$dest" ]; then
    cp "$dest" "$dest.bak-$STAMP" || { echo "FAILED to back up $dest" >&2; exit 1; }
  fi
  cp "$src" "$dest" || { echo "FAILED to install $dest" >&2; exit 1; }
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

# rime.lua: librime-lua resolves lua_processor@NAME and lua_translator@NAME to
# a Lua global of that name defined here. Without it the component is created
# with no error and never runs (spike report, "Deviations from the plan"). The
# names are read from the schema, so a component added there is bound here.
names=$(sed -n 's/^ *- "\{0,1\}lua_[a-z]*@\([A-Za-z0-9_]*\).*/\1/p' rime/luna_pinyin_translate.schema.yaml)
[ -n "$names" ] || { echo "FAILED: no Lua component found in the schema" >&2; exit 1; }
touch "$RIME/rime.lua"
for name in $names; do
  BIND="$name = require(\"$name\")"
  if ! grep -qxF "$BIND" "$RIME/rime.lua"; then
    if [ -s "$RIME/rime.lua" ] && [ -n "$(tail -c1 "$RIME/rime.lua")" ]; then
      echo >> "$RIME/rime.lua"
    fi
    printf '%s\n' "$BIND" >> "$RIME/rime.lua"
    echo "bound $name in $RIME/rime.lua"
    lua_changed=1
  fi
done

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
# idle when a cloud backend is configured. A failure here is reported and the
# run goes on: the IME itself does not depend on the service.
DOMAIN="gui/$(id -u)"
plist_changed=0
if [ ! -f "$AGENTS/$PLIST.plist" ] || ! cmp -s "launchd/$PLIST.plist" "$AGENTS/$PLIST.plist"; then
  if cp "launchd/$PLIST.plist" "$AGENTS/$PLIST.plist"; then
    echo "installed $AGENTS/$PLIST.plist"
    plist_changed=1
  else
    echo "FAILED to install $AGENTS/$PLIST.plist: the IME is installed, the local backend is not" >&2
    status=1
  fi
fi
if [ "$plist_changed" = 1 ]; then
  launchctl bootout "$DOMAIN/$PLIST" 2>/dev/null || true
  for _ in $(seq 50); do
    launchctl print "$DOMAIN/$PLIST" >/dev/null 2>&1 || break
    sleep 0.2
  done
fi
if [ -f "$AGENTS/$PLIST.plist" ] && ! launchctl print "$DOMAIN/$PLIST" >/dev/null 2>&1; then
  if launchctl bootstrap "$DOMAIN" "$AGENTS/$PLIST.plist"; then
    echo "started $PLIST"
  else
    echo "FAILED to start $PLIST: the IME is installed, the local backend is not" >&2
    status=1
  fi
fi

"$SQUIRREL" --reload
echo "Squirrel: redeployed"

if [ "$status" = 0 ]; then echo; echo "Install complete."; else echo; echo "Install finished with errors: see FAILED above."; fi
cat <<'EOF'
If this is a new machine:
  1. System Settings -> Keyboard -> Input Sources: add Squirrel (one-off; if
     it is missing, log out and in once -- Squirrel installed mid-session is
     not listed)
  2. Download the Chinese -> English translation model: System Settings ->
     General -> Language & Region -> Translation Languages
Then Ctrl+Shift+T switches between luna_pinyin_simp and the translation schema.
In the translation schema, Enter after pinyin keeps it as English letters, and
a Shift tap switches between Chinese and English.
EOF
exit "$status"
