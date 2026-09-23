#!/usr/bin/env bash
# Harness self-test. A hook that never fires is worse than no hook: it supplies
# false confidence. Each case feeds a realistically shaped PreToolUse payload
# and asserts the exit code (or, for the injection hook, what got injected).
#
# Run: .claude/hooks/tests/run-hook-tests.sh

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
hooks="$(dirname "$here")"
export CLAUDE_PROJECT_DIR="$(cd "$hooks/../.." && pwd -P)"

pass=0; fail=0

# run <expected exit code> <description> <hook> <payload json>
run() {
  local want="$1" desc="$2" hook="$3" payload="$4"
  local got; printf '%s' "$payload" | bash "$hooks/$hook" >/dev/null 2>&1; got=$?
  if [[ "$got" == "$want" ]]; then
    printf '  ok   %s\n' "$desc"; pass=$((pass+1))
  else
    printf '  FAIL %s (expected exit %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

j() { jq -cn --arg f "$1" --arg c "$2" '{tool_input: {file_path: $f, content: $c}}'; }
jb() { jq -cn --arg c "$1" '{tool_input: {command: $c}}'; }

gate=$(jq -r '.gate.status' "$CLAUDE_PROJECT_DIR"/docs/features/*/progress.json | head -1)

echo "gate-spike.sh  (gate is currently: ${gate})"
if [[ "$gate" == "pass" ]]; then
  run 0 "gate passed: rime/ allowed" gate-spike.sh "$(j "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/json.lua" 'local M = {}')"
else
  run 2 "gate open: refuse rime/" gate-spike.sh "$(j "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/json.lua" 'local M = {}')"
  run 2 "gate open: refuse tests/" gate-spike.sh "$(j "tests/test_json_encode.lua" 'assert(true)')"
fi
run 0 "docs/ always allowed (the spike report must be writable)" gate-spike.sh "$(j "$CLAUDE_PROJECT_DIR/docs/spike-report.md" '# report')"
run 0 ".claude/ always allowed (the harness must be editable)" gate-spike.sh "$(j "$CLAUDE_PROJECT_DIR/.claude/settings.json" '{}')"
run 0 "paths outside the repo are none of its business" gate-spike.sh "$(j "/tmp/scratch/x.lua" 'x')"

echo "check-lua-invariants.sh"
run 2 "commit_text in the translator is blocked" check-lua-invariants.sh \
  "$(j "rime/lua/ime_translate_translator.lua" 'env.engine:commit_text(t)')"
run 2 "commit_text in the filter is blocked" check-lua-invariants.sh \
  "$(j "rime/lua/ime_translate_filter.lua" 'engine:commit_text("x")')"
run 0 "commit_text in the processor is the one legal exit" check-lua-invariants.sh \
  "$(j "rime/lua/ime_translate_processor.lua" 'env.engine:commit_text(out)')"
run 2 "%q building a shell command is blocked" check-lua-invariants.sh \
  "$(j "rime/lua/ime_translate/backend.lua" 'io.popen(string.format("curl -d %q", body))')"
run 0 "%q as test message formatting is not a false positive" check-lua-invariants.sh \
  "$(j "tests/test_json_encode.lua" 'assert(a==b, ("#%d %s: got %q want %q"):format(n, msg, a, b))')"
run 0 "non-.lua files are ignored" check-lua-invariants.sh \
  "$(j "README.md" 'engine:commit_text appearing in prose is fine')"

echo "check-secrets.sh"
run 2 "Anthropic key shape is blocked" check-secrets.sh \
  "$(j "rime/ime_translate.yaml" 'api_key_account: anthropic
# sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"
run 2 "OpenAI key shape is blocked" check-secrets.sh \
  "$(j "notes.md" 'key = sk-proj-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB')"
run 2 "a key inside a Bash command is blocked too" check-secrets.sh \
  "$(jb 'echo sk-ant-api03-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC > /tmp/k')"
run 2 "api_key: in yaml is blocked" check-secrets.sh \
  "$(j "rime/ime_translate.yaml" 'api_key: hunter2')"
run 0 "api_key_account: is the correct form" check-secrets.sh \
  "$(j "rime/ime_translate.yaml" 'api_key_account: anthropic')"
run 0 "the <your-key> placeholder is not a false positive" check-secrets.sh \
  "$(j "README.md" 'security add-generic-password -s ime-translate -a anthropic -w <your-key>')"
run 0 "a short sk-xxx placeholder in docs is not a false positive" check-secrets.sh \
  "$(j "docs/design/backend.md" 'a key shaped like sk-xxx')"
# The fixture exemption must stay narrow: this file is exempt (otherwise the
# hook blocks its own test data and the harness cannot be committed); its
# neighbours are not.
run 0 "hook test fixtures are exempt" check-secrets.sh \
  "$(j ".claude/hooks/tests/run-hook-tests.sh" 'sk-ant-api03-DDDDDDDDDDDDDDDDDDDDDDDDDDDDDD')"
run 2 "the exemption does not leak to .claude/hooks/ itself" check-secrets.sh \
  "$(j ".claude/hooks/check-secrets.sh" 'sk-ant-api03-EEEEEEEEEEEEEEEEEEEEEEEEEEEEEE')"

echo "check-language.sh"
run 2 "a Chinese comment in Lua is blocked" check-language.sh \
  "$(j "rime/lua/ime_translate/decide.lua" '-- 纯函数按键决策
local M = {}')"
run 2 "Chinese prose in a doc is blocked" check-language.sh \
  "$(j "docs/design/architecture.md" 'This is fine. 这一行是中文散文，应该被拦下。')"
run 2 "a Chinese commit message in a shell snippet is blocked" check-language.sh \
  "$(j "scripts/install.sh" 'echo "安装完成"')"
run 0 "Chinese inside inline backticks is allowed (quoted data)" check-language.sh \
  "$(j "docs/design/backend.md" 'The message shown is `✗ 翻译超时` when it times out.')"
run 0 "Chinese inside a fenced block is allowed (quoted data)" check-language.sh \
  "$(j "docs/features/001-zh-en-ime/plan/task-04-state.md" 'The strings are:

```lua
conn_refused = "✗ 翻译服务未启动",
```')"
run 0 "state.lua holds the error strings by design" check-language.sh \
  "$(j "rime/lua/ime_translate/state.lua" 'timeout = "✗ 翻译超时",')"
run 0 "config.lua holds the prompt by design" check-language.sh \
  "$(j "rime/lua/ime_translate/config.lua" 'local P = "你是翻译器。只输出译文。"')"
run 0 "eval/ holds the test sentences by design" check-language.sh \
  "$(j "eval/sentences.txt" '收到，我马上看')"
run 0 "the schema name is shown in the macOS menu" check-language.sh \
  "$(j "rime/luna_pinyin_translate.schema.yaml" 'name: 朙月拼音·译')"
# tests/*.lua: string literals are test data, comments are prose
run 0 "a Chinese string literal in a test file is test data" check-language.sh \
  "$(j "tests/test_state.lua" 'eq(state.errors.timeout, "✗ 翻译超时", "timeout string")')"
run 0 "a -- inside a test-file string is not a comment" check-language.sh \
  "$(j "tests/test_decide.lua" "eq(f('a--b'), '中文', \"dashes inside a string\")")"
run 2 "a Chinese comment in a test file is still blocked" check-language.sh \
  "$(j "tests/test_state.lua" '-- 检查八条错误信息
eq(1, 1, "x")')"
run 2 "Chinese quoted inside a test-file comment is still blocked" check-language.sh \
  "$(j "tests/test_state.lua" '-- see "中文" for the expected text')"
run 2 "a Chinese comment after a test-file string is still blocked" check-language.sh \
  "$(j "tests/test_state.lua" 'eq(f("中文"), "x") -- 注释')"
run 2 "a Chinese string in product code is not test data" check-language.sh \
  "$(j "rime/lua/ime_translate/decide.lua" 'local s = "中文"')"
run 0 "pure English passes" check-language.sh \
  "$(j "rime/lua/ime_translate/decide.lua" '-- Pure-function key decisions
local M = {}')"
# A fence must not leave the rest of the file exempt.
run 2 "Chinese after a closed fence is still caught" check-language.sh \
  "$(j "docs/README.md" '```lua
x = "✗ 翻译超时"
```

后面这行中文散文不该被豁免。')"
# Same narrow-exemption discipline as the secrets check: this file is exempt
# (its fixtures must be Chinese), its neighbours are not.
run 0 "hook test fixtures are exempt" check-language.sh \
  "$(j ".claude/hooks/tests/run-hook-tests.sh" '这是夹具里的中文')"
run 2 "the exemption does not leak to .claude/hooks/ itself" check-language.sh \
  "$(j ".claude/hooks/check-language.sh" '# 这是一行中文注释')"
run 0 "a fence inside a blockquote is still a fence" check-language.sh \
  "$(j "docs/design/architecture.md" 'Quoted advice:

> ```yaml
> name: 朙月拼音·译
> ```
>
> and English after it.')"
run 2 "Chinese after a blockquoted fence closes is still caught" check-language.sh \
  "$(j "docs/design/architecture.md" '> ```yaml
> name: 朙月拼音·译
> ```
> 引用块里的中文散文不该被豁免。')"

# An Edit carries a fragment; the hook rebuilds the post-edit file so fence state
# is real. That needs a file on disk, so these run against a sandbox project.
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/ime-langtest.XXXXXX")
mkdir -p "$sandbox/docs"
cat > "$sandbox/docs/sample.md" <<'MD'
# Sample

Prose line one.

```yaml
half_shape:
  ',' : 'PLACEHOLDER'
```

Prose line two.
旧的中文散文，早就在文件里了。
MD
je() { jq -cn --arg f "$1" --arg o "$2" --arg n "$3" '{tool_input: {file_path: $f, old_string: $o, new_string: $n}}'; }
CLAUDE_PROJECT_DIR="$sandbox" run 0 "Edit: Chinese data landing inside an existing fence is allowed" check-language.sh \
  "$(je "$sandbox/docs/sample.md" "  ',' : 'PLACEHOLDER'" "  '.' : '。'
  '^' : '中'")"
CLAUDE_PROJECT_DIR="$sandbox" run 2 "Edit: Chinese prose landing outside any fence is blocked" check-language.sh \
  "$(je "$sandbox/docs/sample.md" "Prose line one." "这一行是新写的中文散文。")"
CLAUDE_PROJECT_DIR="$sandbox" run 0 "Edit: Chinese already elsewhere in the file is not blamed on this edit" check-language.sh \
  "$(je "$sandbox/docs/sample.md" "Prose line one." "Prose line one, reworded.")"
CLAUDE_PROJECT_DIR="$sandbox" run 2 "Edit: old_string absent -> fragment judged conservatively, as prose" check-language.sh \
  "$(je "$sandbox/docs/sample.md" "no such text in the file" "  '.' : '中文'")"
CLAUDE_PROJECT_DIR="$sandbox" run 2 "Edit: replace_all is judged on the whole rebuilt file" check-language.sh \
  "$(jq -cn --arg f "$sandbox/docs/sample.md" '{tool_input: {file_path: $f, old_string: "Prose", new_string: "Text", replace_all: true}}')"
rm -rf "$sandbox"

echo "guard-push.sh"
run 2 "an unauthorised push is blocked" guard-push.sh "$(jb 'git push origin main')"
run 2 "force-push is blocked too" guard-push.sh "$(jb 'git push --force origin main')"
run 2 "a push hidden mid-command is still caught" guard-push.sh \
  "$(jb 'make build && git push origin main')"
run 0 "an authorised push goes through" guard-push.sh \
  "$(jb 'git push origin main   # authorized-by-user')"
run 0 "git commit is not gated (the plan commits every task)" guard-push.sh \
  "$(jb 'git commit -m "feat: x"')"
run 0 "unrelated commands are ignored" guard-push.sh "$(jb 'git status --short')"

echo "inject-design-context.sh"
# The injection hook never blocks, so assert on what it injected, not on status.
sess="hooktest-$$"
mark_dir="${TMPDIR:-/tmp}/ime-design-inject-${sess}"
rm -rf "$mark_dir"
ji() { jq -cn --arg f "$1" --arg s "$sess" '{session_id:$s,tool_input:{file_path:$f,content:"x"}}'; }
ctx() { ji "$1" | bash "$hooks/inject-design-context.sh" | jq -r '.hookSpecificOutput.additionalContext // ""'; }

want_has() {  # want_has <description> <file> <substring that must appear>
  local got; got=$(ctx "$2")
  if printf '%s' "$got" | grep -q "$3"; then printf '  ok   %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s (injection lacks "%s")\n' "$1" "$3"; fail=$((fail+1)); fi
}
want_empty() {  # want_empty <description> <file>
  local got; got=$(ctx "$2")
  if [[ -z "$got" ]]; then printf '  ok   %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s (injected when it should not)\n' "$1"; fail=$((fail+1)); fi
}

want_has "backend.lua gets §7 backend contract" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/backend.lua" "7. Translation backend contract"
want_empty "second edit in the same session does not repeat" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/backend.lua"
want_has "processor.lua gets §6.3 never eat text" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate_processor.lua" "6.3 Never eat text"
want_has "session.lua gets §6.1 where state lives" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/session.lua" "6.1 Where state lives"
want_has "schema.yaml gets §5.3 punctuation fallback" \
  "$CLAUDE_PROJECT_DIR/rime/luna_pinyin_translate.schema.yaml" "5.3 Chinese punctuation"
want_has "route.lua gets §8.1 error fallback" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/route.lua" "8.1 Error fallback"
want_has "cache.lua gets §8.3 pre-translation and the cache" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/cache.lua" "8.3 Pre-translation"
want_has "shift_tap.lua gets §5.6 switching the backend" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/shift_tap.lua" "5.6 Switching the translation backend"
want_has "url_guard.lua gets §7.5 the URL guard" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate/url_guard.lua" "URLs are guarded"
want_has "shared.lua gets §6.1 where state lives" \
  "$CLAUDE_PROJECT_DIR/rime/lua/ime_translate_shared.lua" "6.1 Where state lives"
want_empty "README.md is ungoverned, nothing injected" "$CLAUDE_PROJECT_DIR/README.md"
rm -rf "$mark_dir"

echo "open decisions (scripts/open-decisions.sh, progress.sh start)"
# Not a hook, but the same kind of rule: an open design decision must actually
# stop the task it blocks. Runs against a sandbox copy of scripts/ so the real
# ledger is never touched.
sb=$(mktemp -d "${TMPDIR:-/tmp}/ime-decisiontest.XXXXXX")
mkdir -p "$sb/docs/design" "$sb/docs/features/001-demo"
cp -R "$CLAUDE_PROJECT_DIR/scripts" "$sb/scripts"
cat > "$sb/docs/features/001-demo/progress.json" <<'JSON'
{"feature":"001-demo","status":"planned","gate":{"id":"G","status":"pass"},
 "tasks":[{"id":7,"name":"blocked one","status":"planned","dependsOn":[],"acceptance":[]},
          {"id":8,"name":"free one","status":"planned","dependsOn":[],"acceptance":[]}]}
JSON
cat > "$sb/docs/design/decisions.md" <<'MD'
## 13. Decisions
| D9 | outside the markers, must be ignored | x | `001:8` | x |
<!-- open-decisions:start -->
| # | Decision | Waits for | Blocks | Until then |
|---|---|---|---|---|
| D1 | display mechanism | S11 | `001:7,9` | nothing |
| D2 | focus loss | S12 | `-` | nothing |
<!-- open-decisions:end -->
MD
expect() {  # expect <description> <want> <got>
  if [[ "$2" == "$3" ]]; then printf '  ok   %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s (want "%s", got "%s")\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
expect "only rows between the markers count" "D1 D2" "$("$sb/scripts/open-decisions.sh" ids)"
expect "blocking: the named task is blocked" "D1" "$("$sb/scripts/open-decisions.sh" blocking 001-demo 7)"
expect "blocking: a neighbouring task is not" "" "$("$sb/scripts/open-decisions.sh" blocking 001-demo 8)"
expect "blocking: another feature's task 7 is not" "" "$("$sb/scripts/open-decisions.sh" blocking 002-other 7)"
"$sb/scripts/progress.sh" start 7 >/dev/null 2>&1
expect "progress.sh start refuses the blocked task" "1" "$?"
expect "...and leaves the ledger untouched" "planned" "$(jq -r '.tasks[0].status' "$sb/docs/features/001-demo/progress.json")"
"$sb/scripts/progress.sh" start 8 >/dev/null 2>&1
expect "progress.sh start allows the unblocked task" "0" "$?"
ALLOW_OPEN_DECISION=1 "$sb/scripts/progress.sh" start 7 >/dev/null 2>&1
expect "the user's explicit override goes through" "0" "$?"
rm -f "$sb/docs/design/decisions.md"
expect "no decisions file means none open, not an error" "" "$("$sb/scripts/open-decisions.sh" ids)"
# Two features open at once: with no id a command refuses rather than guess, and
# PROGRESS_FEATURE names the one meant -- the only way to for done and gate,
# whose arguments are hashes and a verdict.
mkdir -p "$sb/docs/features/002-demo"
cat > "$sb/docs/features/002-demo/progress.json" <<'JSON'
{"feature":"002-demo","status":"planned",
 "tasks":[{"id":1,"name":"first","status":"planned","dependsOn":[],"acceptance":[]}]}
JSON
"$sb/scripts/progress.sh" done 8 abc1234 >/dev/null 2>&1
expect "done with two features open and no id refuses" "1" "$?"
PROGRESS_FEATURE=001 "$sb/scripts/progress.sh" done 8 abc1234 >/dev/null 2>&1
expect "PROGRESS_FEATURE picks the feature for done" "0" "$?"
expect "...and the commit lands in that ledger" "abc1234" "$(jq -r '.tasks[1].commits[0]' "$sb/docs/features/001-demo/progress.json")"
expect "...not in the other one" "planned" "$(jq -r '.tasks[0].status' "$sb/docs/features/002-demo/progress.json")"
PROGRESS_FEATURE=002 "$sb/scripts/progress.sh" start 1 >/dev/null 2>&1
expect "PROGRESS_FEATURE picks the feature for start" "in_progress" "$(jq -r '.tasks[0].status' "$sb/docs/features/002-demo/progress.json")"
PROGRESS_FEATURE=002 "$sb/scripts/progress.sh" show 7 001 >/dev/null 2>&1
expect "an explicit [id] wins over PROGRESS_FEATURE" "0" "$?"
expect "status of a feature with no gate says so" "gate: none" "$("$sb/scripts/progress.sh" status 002 | sed -n 2p)"
rm -rf "$sb"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
exit $(( fail > 0 ))
