#!/usr/bin/env bash
# SessionStart: one line of orientation, and a warning when the git layer has
# silently switched itself off.
#
# WHY. The git-layer checks only run when core.hooksPath points at .githooks.
# That setting is per-clone and is NOT in the repo: a fresh clone, a reset
# config, or a stray `git config --unset` leaves pre-commit, commit-msg and
# reference-transaction all inert, with no symptom whatsoever. The protection
# disappears exactly when nobody is looking for it, which is the same failure
# shape every other hook here was written to prevent.
#
# BUDGET. Ordinary output is ONE line, roughly 20 tokens. This file exists in a
# harness that was reorganised specifically to cut session-start cost; it must
# not quietly undo that. Anything longer appears only when something is wrong.

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$root" ] || exit 0
cd "$root" 2>/dev/null || exit 0

line="ime-translate"

# Summarise whichever feature is still open. Several open at once is legitimate,
# so say how many rather than picking one.
if command -v jq >/dev/null 2>&1; then
  active=$(grep -l '"status": "\(planned\|in_progress\)"' docs/features/*/progress.json 2>/dev/null | head -2)
  n=$(printf '%s\n' "$active" | grep -c . )
  first=$(printf '%s\n' "$active" | head -1)
  if [ -n "$first" ] && [ -f "$first" ]; then
    name=$(basename "$(dirname "$first")")
    gate=$(jq -r 'if .gate then .gate.status else "-" end' "$first" 2>/dev/null)
    done_n=$(jq -r '[.tasks[] | select(.status=="done")] | length' "$first" 2>/dev/null)
    total=$(jq -r '.tasks | length' "$first" 2>/dev/null)
    line="$line | ${name}: ${done_n}/${total} | gate: ${gate}"
    [ "$n" -gt 1 ] && line="$line | +$((n-1)) more open"
  fi
fi

# Open design decisions: a handful of tokens, and the one fact a fresh session
# most needs -- part of the design it is about to read is not settled. Silent
# when nothing is open, so the line shrinks back by itself.
if [ -x scripts/open-decisions.sh ]; then
  open=$(scripts/open-decisions.sh ids 2>/dev/null)
  [ -n "$open" ] && line="$line | open decisions: $open"
fi

if [ "$(git config --get core.hooksPath 2>/dev/null)" = ".githooks" ]; then
  printf '%s | hooks: ok\n' "$line"
else
  printf '%s | hooks: OFF\n\n' "$line"
  printf 'git hooks are NOT installed (core.hooksPath is unset or wrong).\n'
  printf 'The commit-time checks and the protected-branch guard are inert.\n'
  printf 'Fix: ./scripts/setup-harness.sh\n'
fi
exit 0
