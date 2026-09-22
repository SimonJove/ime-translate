#!/usr/bin/env bash
# PreToolUse(Edit|Write): the S1/S3/S11 life-or-death gate. Logic lives in
# lib/checks.sh, shared with .githooks/pre-commit.
payload=$(cat)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd -P)}"
. "$here/lib/checks.sh"

if command -v jq >/dev/null 2>&1; then
  file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
else
  file=$(printf '%s' "$payload" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
[[ -z "$file" ]] && exit 0
rel=$(checks_relpath "$file") || exit 0
checks_gate "$rel" || exit 2
exit 0
