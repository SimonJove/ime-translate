#!/usr/bin/env bash
# PreToolUse(Edit|Write): the first time a session touches a file, inject the
# design sections that govern it.
#
# The design set is ~550 lines. Keeping it resident is expensive, and expecting
# a re-read before every edit is unrealistic — the result is writing from
# memory, then having review catch "timeout_ms became 3000" or "took
# content[0]" — deviations that were entirely avoidable.
#
# So it is delivered on demand: the moment backend.lua is edited, §7 is already
# in context, and it arrives **before** the edit applies — the only moment when
# nothing is wrong yet. Once per rule per session, so a long session pays once.
#
# Never blocks, never fails a tool call: any problem here just means no
# injection.

payload=$(cat)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd -P)}"
[[ -x "$root/scripts/design-section.sh" ]] || exit 0

field() { printf '%s' "$payload" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
file=$(field file_path)
[[ -z "$file" ]] && exit 0
base=$(basename "$file")

session=$(field session_id); : "${session:=nosession}"
mark_dir="${TMPDIR:-/tmp}/ime-design-inject-${session//[^A-Za-z0-9-]/_}"

# file -> the sections that govern it. These are "the few things most easily
# misremembered while writing this file", not "everything vaguely related":
# injecting more than two or three sections is the same as injecting none,
# because it gets skimmed.
secs=""; key=""
case "$base" in
  ime_translate_processor.lua)  key=processor;  secs="5.2 6.2 6.3 6.4" ;; # keys, 2 invalidation checks, never eat text, prompt display
  backend.lua)                  key=backend;    secs="7" ;;             # all three adapters
  config.lua)                   key=config;     secs="7.2 9" ;;         # tiered trust, config keys
  session.lua)                  key=session;    secs="6.1 6.4" ;;       # where state lives, the prompt text
  decide.lua)                   key=decide;     secs="5.2 5.4" ;;       # key table, busy unreachable
  state.lua)                    key=state;      secs="8.1" ;;           # the eight error codes
  json.lua)                     key=json;       secs="7.3" ;;           # why shq and not %q
  ime_translate_shared.lua)     key=shared;     secs="5.6 6.1" ;;       # the active slot, what may be process-wide
  route.lua)                    key=route;      secs="8.1 8.2 8.3" ;;   # the fallback, the freeze budget, the cache
  cache.lua)                    key=cache;      secs="8.3 6.1" ;;       # what is cached, why process-wide is allowed
  shift_tap.lua)                key=tap;        secs="5.5 5.6" ;;       # the Shift tap, the Right Option tap
  url_guard.lua)                key=urlguard;   secs="7.5" ;;           # the placeholders and when they fail
  *.schema.yaml)                key=schema;     secs="4.1 5.1 5.3" ;;   # components, switching, punctuation
  ime_translate.yaml)           key=userconf;   secs="9 7.3" ;;         # config keys, secrets red line
esac
[[ -z "$secs" ]] && exit 0
[[ -e "$mark_dir/$key" ]] && exit 0

body=$(cd "$root" && ./scripts/design-section.sh $secs 2>/dev/null)
[[ -z "$body" ]] && exit 0

mkdir -p "$mark_dir" 2>/dev/null
: > "$mark_dir/$key" 2>/dev/null

text="=== design §${secs// /, §} — injected because you are editing ${base}; once per session ===

${body}
(That is the design as written. Where the implementation differs, either change
the implementation or change the design and say so — do not deviate silently.)
"

if command -v jq >/dev/null 2>&1; then
  printf '%s' "$text" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:.}}'
fi
exit 0
