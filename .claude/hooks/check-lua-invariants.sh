#!/usr/bin/env bash
# PreToolUse(Edit|Write): one commit exit + shell escaping via json.shq only.
# Without jq, skip: parsing a multi-line JSON body with sed is unreliable, and
# not checking beats misjudging.
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd -P)}"
. "$here/lib/checks.sh"

file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
body=$(printf '%s' "$payload" | jq -r '[.tool_input.content, .tool_input.new_string] | map(select(. != null)) | join("\n")')
[[ -z "$file" ]] && exit 0
rel=$(checks_relpath "$file") || rel="$file"
checks_lua_invariants "$rel" "$body" || exit 2
exit 0
