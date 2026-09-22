#!/usr/bin/env bash
# The only read/write entry point for docs/features/*/progress.json.
#
# Why a script instead of ad-hoc jq each time: progress.json is the source of
# truth for execution state, and hand-rolled jq easily overwrites the whole
# tasks array or writes local time into startedAt. Each kind of change is one
# subcommand here: minimal edit, UTC timestamps throughout.
#
#   progress.sh status [id]       overview: gate + every task
#   progress.sh show <n> [id]     one task (deps, acceptance, deliverables)
#   progress.sh next [id]         which task is unblocked and ready to start
#   progress.sh start <n> [id]    mark in_progress, record startedAt + baseline
#   progress.sh done <n> [hash…]  mark done, record completedAt, append commits
#   progress.sh diffrange <n>     the diff range to review for that task
#   progress.sh gate <pass|fail>  record the S1/S3/S11 life-or-death verdict
#   progress.sh features          list every feature and its state
#   progress.sh decisions         design decisions still open, and what they block
#
# [id] selects a feature -- a full directory name, or a prefix such as "001" or
# "zh-en". With no id, PROGRESS_FEATURE=<id> is used if set; otherwise the
# single feature that is in_progress or planned. If several qualify, the
# command says so rather than guessing. `done` and `gate` take no [id] -- their
# arguments are hashes and a verdict -- so with two features open,
# PROGRESS_FEATURE is how to name one for them.
#
# Exit codes: 0 fine; 1 usage or state error.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FEATURES="$root/docs/features"

# Resolve a feature directory. Guessing wrong here would write a task update
# into the wrong feature's ledger, so an ambiguous match refuses instead.
resolve_feature() {
  local want="${1:-${PROGRESS_FEATURE:-}}" hits=() d
  for d in "$FEATURES"/*/; do
    [[ -f "$d/progress.json" ]] || continue
    if [[ -z "$want" ]]; then
      case "$(jq -r '.status' "$d/progress.json")" in
        done|archived) continue ;;
      esac
      hits+=("$d")
    else
      case "$(basename "$d")" in *"$want"*) hits+=("$d") ;; esac
    fi
  done
  if [[ ${#hits[@]} -eq 1 ]]; then printf '%s' "${hits[0]%/}"; return 0; fi
  if [[ ${#hits[@]} -eq 0 ]]; then
    echo "no feature matches '${want:-<active>}'. Try: progress.sh features" >&2; return 1
  fi
  { echo "'${want:-<active>}' matches several features; name one, as [id] or PROGRESS_FEATURE=<id>:"
    for d in "${hits[@]}"; do echo "  $(basename "${d%/}")"; done; } >&2
  return 1
}

cmd_features() {
  local d
  for d in "$FEATURES"/*/; do
    [[ -f "$d/progress.json" ]] || continue
    jq -r --arg name "$(basename "${d%/}")" '
      "\($name)  [\(.status)]  \([.tasks[] | select(.status=="done")] | length)/\(.tasks | length)" +
      (if .gate then "  gate \(.gate.id): \(.gate.status)" else "" end)' "$d/progress.json"
  done
}

command -v jq >/dev/null 2>&1 || { echo "jq required: brew install jq" >&2; exit 1; }
[[ -d "$FEATURES" ]] || { echo "not found: $FEATURES" >&2; exit 1; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Open design decisions (docs/design/decisions.md, read only through
# open-decisions.sh). A missing script means "none open", never an error.
decisions() { [[ -x "$root/scripts/open-decisions.sh" ]] && "$root/scripts/open-decisions.sh" "$@" || true; }

cmd_decisions() {
  local rows; rows="$(decisions list)"
  if [[ -z "$rows" ]]; then echo "no open design decisions"; return 0; fi
  printf '%s\n' "$rows" | while IFS=$'\t' read -r id blocks waits what; do
    printf '%s  blocks: %s  waits for: %s\n    %s\n' "$id" "$blocks" "$waits" "$what"
  done
  echo
  echo "detail: docs/design/decisions.md, \"Open decisions\""
}

# Atomic write: a failing jq must not truncate the original to empty.
# $f is a local in each cmd_*, so it is passed explicitly as the last argument.
save() {
  local file="${!#}"; set -- "${@:1:$#-1}"
  local tmp; tmp="$(mktemp)"
  if jq "$@" "$file" > "$tmp"; then mv "$tmp" "$file"; else rm -f "$tmp"; echo "jq failed; progress.json unchanged" >&2; exit 1; fi
}

task_exists() { jq -e --argjson i "$1" '.tasks[] | select(.id == $i)' "$2" >/dev/null 2>&1; }

cmd_status() {
  local f; f="$(resolve_feature "${1:-}")/progress.json" || return 1
  jq -r --arg fname "$(basename "$(dirname "$f")")" '
    def mark: if . == "done" then "✅" elif . == "in_progress" then "🔨"
              elif . == "blocked" then "⛔" elif . == "skipped" then "⏭ " else "⬜" end;
    "feature: \($fname)    plan: \(.plan)",
    (if .gate then "gate \(.gate.id): \(
       if .gate.status == "pass" then "PASSED"
       elif .gate.status == "fail" then "FALSIFIED - Plan A′ does not exist; stop implementing"
       else "UNVERIFIED - no implementation code for Tasks 2-12 yet" end)"
     else "gate: none" end),
    "",
    (.tasks[] |
      "\(.status | mark) Task \(.id | tostring | (" " * (2 - length)) + .)  \(.name)" +
      (if .gate then "   [gate \(.gate)]" else "" end) +
      (if .manual then "   (manual / real machine)" else "" end)),
    "",
    "progress: \([.tasks[] | select(.status == "done")] | length)/\(.tasks | length) done"
  ' "$f"
  local open; open="$(decisions list)"
  if [[ -n "$open" ]]; then
    echo "open design decisions (progress.sh decisions):"
    printf '%s\n' "$open" | while IFS=$'\t' read -r id blocks waits _; do
      printf '  %s  blocks: %s  waits for: %s\n' "$id" "$blocks" "$waits"
    done
  fi
}

cmd_show() {
  local i="$1"; local f; f="$(resolve_feature "${2:-}")/progress.json" || return 1
  task_exists "$i" "$f" || { echo "no Task $i" >&2; exit 1; }
  jq -r --argjson i "$i" '
    .tasks[] | select(.id == $i) |
    "Task \(.id): \(.name)    [\(.status)]",
    "  \(.description)",
    "",
    "depends on: \(.dependsOn // [] | if length == 0 then "nothing" else map("Task \(.)") | join(", ") end)",
    "deliverables: \(.deliverables // [] | join(", "))",
    (if .test then "unit test: \(.test)" else empty end),
    (if .gate then "gate: \(.gate)" else empty end),
    "",
    "acceptance:",
    (.acceptance[] | "  - \(.)"),
    "",
    "plan file: \(.planAnchor)"
  ' "$f"
}

cmd_next() {
  local f; f="$(resolve_feature "${1:-}")/progress.json" || return 1
  jq -r '
    (.tasks | map(select(.status == "done") | .id)) as $done |
    [.tasks[] | select(.status == "planned")
              | select(((.dependsOn // []) - $done) | length == 0)] as $ready |
    if ($ready | length) == 0 then
      ([.tasks[] | select(.status == "in_progress")] | if length > 0
        then "Task \(.[0].id) is still in_progress; close it first"
        else "nothing left to start" end)
    else ($ready | map("Task \(.id): \(.name)") | join("\n")) end
  ' "$f"
}

cmd_start() {
  local i="$1"; local f; f="$(resolve_feature "${2:-}")/progress.json" || return 1
  task_exists "$i" "$f" || { echo "no Task $i" >&2; exit 1; }
  # Dependency gate: an unmet prerequisite may not be skipped silently
  local unmet
  unmet=$(jq -r --argjson i "$i" '
    (.tasks | map(select(.status == "done") | .id)) as $done |
    (.tasks[] | select(.id == $i) | (.dependsOn // []) - $done) | map(tostring) | join(", ")' "$f")
  if [[ -n "$unmet" ]]; then
    echo "Task $i depends on $unmet, which is not done. Skipping must be your explicit decision: set that task's status to skipped in progress.json." >&2
    exit 1
  fi
  # Decision gate: a task that builds on an undecided part of the design does
  # not start. Written only in a document, "do not build on §6 yet" loses to
  # "Task 7 is unblocked, let me just start" -- the same reasoning as the spike
  # gate. The override is the user's: an agent does not set it for itself.
  local feat blocked
  feat="$(basename "$(dirname "$f")")"
  blocked="$(decisions blocking "$feat" "$i")"
  if [[ -n "$blocked" && "${ALLOW_OPEN_DECISION:-0}" != "1" ]]; then
    { echo "Task $i is blocked by open design decision(s): $blocked"
      echo
      decisions list | while IFS=$'\t' read -r id _ waits what; do
        case " $blocked " in *" $id "*) printf '  %s (waits for: %s)\n    %s\n' "$id" "$waits" "$what" ;; esac
      done
      echo
      echo "The part of the design this task builds on is not settled. Close the decision"
      echo "first: delete its row from docs/design/decisions.md \"Open decisions\" and record"
      echo "the outcome there. That is the user's call, not an agent's."
      echo "Deliberate override, by the user only: ALLOW_OPEN_DECISION=1 $0 start $i"
    } >&2
    exit 1
  fi
  # Record the baseline commit: at close time the reviewer needs to know which
  # diff to read. Without it, the only option is "roughly the last few commits",
  # which necessarily misses things once a task spans several commits.
  local base; base=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo "")
  save --argjson i "$i" --arg t "$(now)" --arg b "$base" \
    '(.tasks[] | select(.id == $i)) |= (.status = "in_progress" | .startedAt = $t | .baseCommit = $b)
     | .status = "in_progress"' "$f"
  echo "Task $i -> in_progress ($(now))"
  # An `if`, not `[[ … ]] && echo`: as the function's last command the short
  # form made a successful start exit 1 whenever there was no baseline commit.
  if [[ -n "$base" ]]; then echo "baseline commit: ${base:0:8}  (review ${base:0:8}..HEAD at close)"; fi
}

cmd_done() {
  local i="$1"; shift; local f; f="$(resolve_feature "")/progress.json" || return 1
  task_exists "$i" "$f" || { echo "no Task $i" >&2; exit 1; }
  local hashes; hashes=$(printf '%s\n' "$@" | jq -R . | jq -s 'map(select(. != ""))')
  save --argjson i "$i" --arg t "$(now)" --argjson h "$hashes" \
    '(.tasks[] | select(.id == $i)) |= (.status = "done" | .completedAt = $t | .commits += $h)
     | .status = (if ([.tasks[] | select(.status != "done" and .status != "skipped")] | length) == 0
                  then "done" else "in_progress" end)' "$f"
  echo "Task $i -> done ($(now))${*:+, commit $*}"
  cmd_next
}

# The range the reviewer should read. With no baseline, fall back to HEAD.
cmd_diffrange() {
  local i="$1"; local f; f="$(resolve_feature "${2:-}")/progress.json" || return 1
  task_exists "$i" "$f" || { echo "no Task $i" >&2; exit 1; }
  local base; base=$(jq -r --argjson i "$i" '.tasks[] | select(.id == $i) | .baseCommit // ""' "$f")
  if [[ -n "$base" ]] && git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null; then
    echo "${base}..HEAD"
  else
    echo "HEAD"   # no baseline: review HEAD vs the working tree
  fi
}

cmd_gate() {
  local f; f="$(resolve_feature "")/progress.json" || return 1
  case "${1:-}" in
    pass) save --arg t "$(now)" '.gate.status = "pass" | .gate.verifiedAt = $t' "$f"
          echo "gate S1/S3/S11 -> pass. Tasks 2-12 unlocked." ;;
    fail) save --arg t "$(now)" '.gate.status = "fail" | .gate.verifiedAt = $t' "$f"
          echo "gate S1/S3/S11 -> fail. Stop implementing and return to design."
          echo "  S1 or S3 falsified: Plan A′ does not exist -- evaluate Plan B′ (design §3.5)."
          echo "  S11 falsified: design §6.1-§6.2 go back to design review; A′ may still stand." ;;
    *) echo "usage: progress.sh gate <pass|fail>" >&2; exit 1 ;;
  esac
}

case "${1:-status}" in
  status)   cmd_status "${2:-}" ;;
  show)     cmd_show "${2:?usage: progress.sh show <n> [feature]}" "${3:-}" ;;
  next)     cmd_next "${2:-}" ;;
  start)    cmd_start "${2:?usage: progress.sh start <n> [feature]}" "${3:-}" ;;
  done)     shift; cmd_done "${1:?usage: progress.sh done <n> [hash…]}" "${@:2}" ;;
  gate)     cmd_gate "${2:-}" ;;
  diffrange) cmd_diffrange "${2:?usage: progress.sh diffrange <n>}" "${3:-}" ;;
  features) cmd_features ;;
  decisions) cmd_decisions ;;
  *) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
