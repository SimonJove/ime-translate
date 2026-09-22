#!/usr/bin/env bash
# One-off: wire the harness up, then health-check it.
#
# The one thing that genuinely needs this script is `git config core.hooksPath`:
# git does not discover .githooks/ on its own, and `git config` sits in
# .claude/settings.json's deny list (an agent has no business changing your git
# configuration), so this step can only be run by you.
#
#   ./scripts/setup-harness.sh          install
#   ./scripts/setup-harness.sh --check  health-check only, changes nothing

set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
check_only=0; [[ "${1:-}" == "--check" ]] && check_only=1

ok=0; bad=0
say() { printf '%s %s\n' "$1" "$2"; }
good() { say "✓" "$1"; ok=$((ok+1)); }
warn() { say "✗" "$1"; bad=$((bad+1)); }

echo "-- dependencies --"
for c in jq lua git python3; do
  if command -v "$c" >/dev/null 2>&1; then good "$c $(command -v $c)"; else warn "$c missing (brew install $c)"; fi
done

echo
echo "-- git hooks --"
current=$(git config --get core.hooksPath 2>/dev/null || echo "")
if [[ "$current" == ".githooks" ]]; then
  good "core.hooksPath already points at .githooks"
elif [[ $check_only -eq 1 ]]; then
  warn "core.hooksPath is '${current:-<default>}' - run ./scripts/setup-harness.sh to set it"
else
  if git config core.hooksPath .githooks; then
    good "core.hooksPath -> .githooks"
  else
    warn "failed to set core.hooksPath"
  fi
fi
for h in pre-commit commit-msg reference-transaction; do
  if [[ -x ".githooks/$h" ]]; then good ".githooks/$h executable"; else warn ".githooks/$h missing or not executable"; fi
done

echo
echo "-- Claude hooks --"
for h in gate-spike check-lua-invariants check-secrets check-language inject-design-context guard-push session-status; do
  if [[ -x ".claude/hooks/$h.sh" ]]; then good ".claude/hooks/$h.sh"; else warn ".claude/hooks/$h.sh missing or not executable"; fi
done
for s in progress design-section open-decisions; do
  if [[ -x "scripts/$s.sh" ]]; then good "scripts/$s.sh"; else warn "scripts/$s.sh missing or not executable"; fi
done
if jq -e '.hooks.PreToolUse' .claude/settings.json >/dev/null 2>&1; then
  good "settings.json wired ($(jq '[.hooks.PreToolUse[].hooks[]] | length' .claude/settings.json) hooks)"
else
  warn "settings.json has no PreToolUse wiring"
fi

echo
echo "-- self-test --"
if .claude/hooks/tests/run-hook-tests.sh >/tmp/hooktest.$$ 2>&1; then
  good "Claude-hook self-test: $(tail -1 /tmp/hooktest.$$)"
else
  warn "Claude-hook self-test failed; run .claude/hooks/tests/run-hook-tests.sh"
  tail -5 /tmp/hooktest.$$
fi
rm -f /tmp/hooktest.$$

if .githooks/tests/run-githook-tests.sh >/tmp/githooktest.$$ 2>&1; then
  good "git-layer self-test: $(tail -1 /tmp/githooktest.$$)"
else
  warn "git-layer self-test failed; run .githooks/tests/run-githook-tests.sh"
  tail -5 /tmp/githooktest.$$
fi
rm -f /tmp/githooktest.$$

bad_ledger=0
for led in docs/features/*/progress.json; do
  [ -f "$led" ] || continue
  if jq empty "$led" 2>/dev/null; then
    good "$(basename "$(dirname "$led")"): valid (gate: $(jq -r 'if .gate then .gate.status else "-" end' "$led"))"
  else
    warn "$led is not valid JSON"; bad_ledger=1
  fi
done
[ "$bad_ledger" = 0 ] || true

echo
if [[ $bad -eq 0 ]]; then
  echo "harness ready ($ok checks). Next:"
  echo "  ./scripts/progress.sh status"
  echo "  /task-start        # begin with Task 1, the spike"
else
  echo "$ok fine, $bad need attention."
fi
exit $(( bad > 0 ))
