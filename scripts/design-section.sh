#!/usr/bin/env bash
# Print one numbered section from the docs/design/ set, verbatim.
#
#   design-section.sh 6.2          -> just §6.2
#   design-section.sh 7            -> §7 and every 7.x under it
#   design-section.sh 5.2 6.2 6.3  -> three sections concatenated
#
# Section numbers are stable IDs and are resolved across every file in
# docs/design/, so splitting or moving a file does not break a reference.
#
# Used by inject-design-context.sh; also fine to run by hand. The design set is
# ~550 lines: reading all of it to check one constant is both expensive and
# self-defeating, since a long read gets skimmed.

set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
dir="$root/docs/design"
[[ -d "$dir" ]] || { echo "no $dir" >&2; exit 1; }
[[ $# -gt 0 ]] || { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

for sec in "$@"; do
  found=0
  for doc in "$dir"/*.md; do
    out=$(awk -v want="$sec" '
      function esc(s) { gsub(/\./, "\\.", s); return s }
      BEGIN { want_re = "^#+ " esc(want) "[.[:space:]]"
              child_re = "^#+ " esc(want) "\\."
              printing = 0 }
      {
        if ($0 ~ want_re) { printing = 1; print; next }
        if (printing && $0 ~ child_re) { print; next }
        if (printing && $0 ~ /^#+ [0-9]+[.[:space:]]/) { printing = 0 }
        if (printing) print
      }
    ' "$doc")
    if [[ -n "$out" ]]; then
      printf '<!-- docs/design/%s -->\n%s\n' "$(basename "$doc")" "$out"
      found=1; break
    fi
  done
  [[ $found -eq 0 ]] && echo "section $sec not found in docs/design/" >&2
done
