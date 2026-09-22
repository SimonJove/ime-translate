#!/usr/bin/env bash
# The design decisions that are still open -- the only parser of that table.
#
#   open-decisions.sh                         ID <tab> blocks <tab> waits for <tab> decision
#   open-decisions.sh ids                     the IDs on one line ("" when none)
#   open-decisions.sh blocking <feature> <n>  IDs that block Task <n> of <feature>
#
# Source of truth: the table between the two open-decisions markers in
# docs/design/decisions.md. A row there IS an open decision; closing one means
# deleting its row and writing the outcome as a dated entry below it.
#
# Why a script: an open decision written only in prose loses to "let me just
# start Task 7, it is unblocked". progress.sh refuses to start a task a row
# blocks, and the session-start line names what is open -- both through here, so
# the table format has exactly one reader.
#
# The Blocks cell holds tokens like 001:7,9 (feature number, colon, task list),
# space separated, or "-" for nothing. Cells must not contain a literal "|".
#
# Never fails the caller: no file, no markers or no rows all mean "none open".

set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
file="$root/docs/design/decisions.md"
[[ -f "$file" ]] || exit 0

rows() {
  awk -F'|' '
    /<!-- open-decisions:start -->/ { on = 1; next }
    /<!-- open-decisions:end -->/   { on = 0 }
    on && $2 ~ /^[[:space:]]*D[0-9]+[[:space:]]*$/ {
      for (i = 2; i <= 5; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
      gsub(/`/, "", $5)
      printf "%s\t%s\t%s\t%s\n", $2, $5, $4, $3
    }' "$file"
}

case "${1:-list}" in
  list) rows ;;
  ids)  rows | cut -f1 | tr '\n' ' ' | sed 's/ $//' ;;
  blocking)
    feature="${2:?usage: open-decisions.sh blocking <feature> <n>}"
    task="${3:?usage: open-decisions.sh blocking <feature> <n>}"
    num="${feature%%-*}"          # 001-zh-en-ime -> 001
    rows | awk -F'\t' -v num="$num" -v task="$task" '
      { n = split($2, toks, /[[:space:]]+/)
        for (i = 1; i <= n; i++) {
          if (split(toks[i], kv, ":") != 2 || kv[1] != num) continue
          m = split(kv[2], ts, ",")
          for (j = 1; j <= m; j++) if (ts[j] == task) { print $1; next }
        } }' | tr '\n' ' ' | sed 's/ $//'
    ;;
  *) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
exit 0
