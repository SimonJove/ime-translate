#!/usr/bin/env bash
# PreToolUse(Edit|Write|Bash): the API key red line. Bash is checked too —
# `echo sk-… > file` must not slip past.
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd -P)}"
. "$here/lib/checks.sh"

file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
body=$(printf '%s' "$payload" | jq -r '[.tool_input.content, .tool_input.new_string, .tool_input.command] | map(select(. != null)) | join("\n")')
[[ -z "$body" ]] && exit 0
if [[ -n "$file" ]]; then rel=$(checks_relpath "$file") || rel="$file"; else rel=""; fi
checks_secrets "$rel" "$body" || exit 2
exit 0
