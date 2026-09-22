#!/usr/bin/env bash
# Self-test for the git-layer hooks.
#
# The Claude hooks have had a suite since day one; these did not, and were only
# ever dry-run by hand. That matters most for reference-transaction, whose two
# failure modes are both silent:
#   - it stops protecting (a real `git branch -D main` goes through), or
#   - it over-protects (every `git gc` / `pack-refs` aborts with a scary error).
# Neither announces itself. Only a test does.
#
# Each case runs in a disposable repo under $TMPDIR with core.hooksPath pointed
# at the real .githooks, so what is exercised is the shipped hook, not a copy.
#
# Run: .githooks/tests/run-githook-tests.sh

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOKS="$(dirname "$here")"
pass=0; fail=0

ok()    { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()   { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected exit $1, got $2)"; fi; }
# git returns 128 -- not 1 -- when a hook aborts a ref transaction, so a refusal
# is asserted as "non-zero" rather than a fixed code.
blocked() { if [ "$1" -ne 0 ]; then ok "$2"; else bad "$2 (expected a refusal, got exit 0)"; fi; }

# A throwaway repo with one commit on main, hooks wired to the real .githooks.
mkrepo() {
  local d; d=$(mktemp -d)
  git -C "$d" init -q -b main
  git -C "$d" config core.hooksPath "$HOOKS"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  echo x > "$d/f"
  git -C "$d" add f
  # The repo's own commit-msg hook is live here, so this subject must be valid.
  git -C "$d" commit -qm "chore: seed" >/dev/null 2>&1
  printf '%s' "$d"
}

echo "reference-transaction"

r=$(mkrepo)
git -C "$r" branch other
git -C "$r" checkout -q other
git -C "$r" branch -D main >/dev/null 2>&1; blocked $? "git branch -D main is refused"
git -C "$r" rev-parse --verify -q main >/dev/null 2>&1; check 0 $? "main still exists afterwards"
rm -rf "$r"

r=$(mkrepo)
git -C "$r" branch scratch
git -C "$r" branch -D scratch >/dev/null 2>&1; check 0 $? "an ordinary branch deletes fine"
rm -rf "$r"

r=$(mkrepo)
git -C "$r" branch other
git -C "$r" checkout -q other
ALLOW_PROTECTED_BRANCH_DELETE=1 git -C "$r" branch -D main >/dev/null 2>&1
check 0 $? "the escape hatch works"
rm -rf "$r"

# The regression that made the upstream version unusable at first: pack-refs
# removes the loose ref while the branch survives, and gc --auto runs it.
r=$(mkrepo)
git -C "$r" pack-refs --all >/dev/null 2>&1; check 0 $? "git pack-refs --all is not mistaken for a delete"
git -C "$r" rev-parse --verify -q main >/dev/null 2>&1; check 0 $? "main survives the pack"
git -C "$r" branch other >/dev/null 2>&1
git -C "$r" checkout -q other
git -C "$r" branch -D main >/dev/null 2>&1; blocked $? "deleting an already-packed main is still refused"
rm -rf "$r"

r=$(mkrepo)
git -C "$r" gc --quiet >/dev/null 2>&1; check 0 $? "git gc does not abort"
rm -rf "$r"

r=$(mkrepo)
echo y > "$r/g"; git -C "$r" add g
git -C "$r" commit -qm "feat: another" >/dev/null 2>&1; check 0 $? "an ordinary commit is unaffected"
git -C "$r" checkout -qb feat/x >/dev/null 2>&1; check 0 $? "creating a branch is unaffected"
rm -rf "$r"

echo "commit-msg"

r=$(mkrepo)
echo z > "$r/h"; git -C "$r" add h
git -C "$r" commit -qm "update" >/dev/null 2>&1; check 1 $? "a bare 'update' subject is refused"
git -C "$r" commit -qm "feat: add the thing" >/dev/null 2>&1; check 0 $? "a conventional subject is accepted"
rm -rf "$r"

r=$(mkrepo)
echo z > "$r/h"; git -C "$r" add h
long="feat: $(printf 'x%.0s' $(seq 1 90))"
git -C "$r" commit -qm "$long" >/dev/null 2>&1; check 1 $? "a subject over 72 chars is refused"
rm -rf "$r"

echo "pre-commit"

# checks_gate resolves the gate from docs/features/*/progress.json. A throwaway
# repo has none, so it steps aside -- its documented fail-open for a foreign
# tree. The next case proves it does NOT step aside once a ledger is present.
r=$(mkrepo)
mkdir -p "$r/rime/lua"
printf 'local x = 1\n' > "$r/rime/lua/probe.lua"
git -C "$r" add rime/lua/probe.lua
git -C "$r" commit -qm "feat: probe" >/dev/null 2>&1; check 0 $? "a tree without progress.json is not gated"
rm -rf "$r"

r=$(mkrepo)
printf 'env.engine:commit_text("x")\n' > "$r/ime_translate_translator.lua"
git -C "$r" add ime_translate_translator.lua
git -C "$r" commit -qm "feat: bad" >/dev/null 2>&1; check 1 $? "commit_text outside the processor is refused at commit time"
rm -rf "$r"

r=$(mkrepo)
printf 'key = sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' > "$r/notes.md"
git -C "$r" add notes.md
git -C "$r" commit -qm "docs: notes" >/dev/null 2>&1; check 1 $? "a real-shaped API key is refused at commit time"
rm -rf "$r"

r=$(mkrepo)
printf -- '-- 中文注释\nlocal M = {}\n' > "$r/mod.lua"
git -C "$r" add mod.lua
git -C "$r" commit -qm "feat: mod" >/dev/null 2>&1; check 1 $? "a Chinese comment is refused at commit time"
rm -rf "$r"

r=$(mkrepo)
mkdir -p "$r/tests"
printf 'eq(f("x"), "中文", "data")\n' > "$r/tests/test_x.lua"
git -C "$r" add tests/test_x.lua
git -C "$r" commit -qm "test: x" >/dev/null 2>&1; check 0 $? "a Chinese string literal in a test file is accepted at commit time"
rm -rf "$r"

r=$(mkrepo)
mkdir -p "$r/tests"
printf -- '-- 中文注释\neq(1, 1, "x")\n' > "$r/tests/test_x.lua"
git -C "$r" add tests/test_x.lua
git -C "$r" commit -qm "test: x" >/dev/null 2>&1; check 1 $? "a Chinese comment in a test file is refused at commit time"
rm -rf "$r"

# With a feature ledger whose gate is unverified, rime/ must be refused.
r=$(mkrepo)
mkdir -p "$r/docs/features/001-x" "$r/rime/lua"
printf '{"status":"planned","gate":{"id":"S1/S3","status":"unverified"},"tasks":[]}\n' \
  > "$r/docs/features/001-x/progress.json"
printf 'local x = 1\n' > "$r/rime/lua/probe.lua"
git -C "$r" add docs rime
git -C "$r" commit -qm "feat: probe" >/dev/null 2>&1; check 1 $? "an unverified gate refuses rime/ at commit time"
rm -rf "$r"

# And a passing gate lets it through.
r=$(mkrepo)
mkdir -p "$r/docs/features/001-x" "$r/rime/lua"
printf '{"status":"in_progress","gate":{"id":"S1/S3","status":"pass"},"tasks":[]}\n' \
  > "$r/docs/features/001-x/progress.json"
printf 'local x = 1\n' > "$r/rime/lua/probe.lua"
git -C "$r" add docs rime
git -C "$r" commit -qm "feat: probe" >/dev/null 2>&1; check 0 $? "a passing gate allows rime/ at commit time"
rm -rf "$r"

echo "session-status (drift detection)"

# This is a Claude hook, not a git hook, but what it detects is git config
# state -- so it is tested here, where the sandbox repo machinery already lives.
STATUS="$(dirname "$HOOKS")/.claude/hooks/session-status.sh"

r=$(mktemp -d)
git -C "$r" init -q -b main
mkdir -p "$r/docs/features/001-x"
cp "$(dirname "$HOOKS")"/docs/features/*/progress.json "$r/docs/features/001-x/" 2>/dev/null
out=$(CLAUDE_PROJECT_DIR="$r" bash "$STATUS" 2>&1)
case "$out" in
  *"hooks: OFF"*) ok "an unset core.hooksPath is reported as OFF" ;;
  *) bad "an unset core.hooksPath should report OFF, got: $(printf '%s' "$out" | head -1)" ;;
esac
case "$out" in
  *"setup-harness.sh"*) ok "the warning names the fix" ;;
  *) bad "the warning should name setup-harness.sh" ;;
esac

git -C "$r" config core.hooksPath .githooks
out=$(CLAUDE_PROJECT_DIR="$r" bash "$STATUS" 2>&1)
case "$out" in
  *"hooks: ok"*) ok "a correct core.hooksPath is reported as ok" ;;
  *) bad "a correct core.hooksPath should report ok, got: $(printf '%s' "$out" | head -1)" ;;
esac
# The healthy path must stay one line: this hook runs on every session start.
n=$(printf '%s' "$out" | wc -l | tr -d ' ')
if [ "$n" -le 1 ]; then ok "the healthy line is a single line"
else bad "the healthy output grew to $((n+1)) lines; it runs every session"; fi
rm -rf "$r"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
exit $(( fail > 0 ))
