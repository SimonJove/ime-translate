#!/usr/bin/env bash
# PreToolUse(Edit|Write): English-only, with the three data exceptions.
# Logic lives in lib/checks.sh, shared with .githooks/pre-commit.
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$here/../.." && pwd -P)}"
. "$here/lib/checks.sh"

file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
[[ -z "$file" ]] && exit 0
rel=$(checks_relpath "$file") || exit 0

# Write carries the whole file: check it as it is.
content=$(printf '%s' "$payload" | jq -r '.tool_input.content // empty')
if [[ -n "$content" ]]; then
  checks_language "$rel" "$content" || exit 2
  exit 0
fi

# Edit carries only a fragment, and fence state is unknowable from a fragment:
# a replacement that sits inside a ```block``` looks exactly like prose. Judging
# it as prose refused legitimate edits (twice on 2026-09-20, both quoting
# Chinese punctuation inside a fenced YAML block) -- and a hook that cries wolf
# gets switched off. So rebuild the file as it will be after the edit and check
# that, reporting only the lines the replacement occupies.
new=$(printf '%s' "$payload" | jq -r '.tool_input.new_string // empty')
[[ -z "$new" ]] && exit 0
old=$(printf '%s' "$payload" | jq -r '.tool_input.old_string // empty')
all=$(printf '%s' "$payload" | jq -r '.tool_input.replace_all // false')

abs="$file"; [[ "$abs" == /* ]] || abs="$PROJECT_ROOT/$abs"
rebuilt=""
if [[ -f "$abs" && -n "$old" ]]; then
  # First line out: "<first>:<last>" of the replaced lines ("0:0" = whole file,
  # used for replace_all). Then the rebuilt file. Exit 3: old_string not found.
  rebuilt=$(FILE="$abs" OLD="$old" NEW="$new" ALL="$all" perl -e '
    local $/; open(my $fh, "<:raw", $ENV{FILE}) or exit 3; my $c = <$fh>;
    my ($old, $new) = ($ENV{OLD}, $ENV{NEW});
    my $i = index($c, $old); exit 3 if $i < 0;
    if ($ENV{ALL} eq "true") { $c =~ s/\Q$old\E/$new/g; print "0:0\n" }
    else {
      my $first = (substr($c, 0, $i) =~ tr/\n//) + 1;
      substr($c, $i, length $old) = $new;
      print $first, ":", $first + ($new =~ tr/\n//), "\n";
    }
    print $c;
  ' 2>/dev/null) || rebuilt=""
fi

if [[ -n "$rebuilt" ]]; then
  range="${rebuilt%%$'\n'*}"
  checks_language "$rel" "${rebuilt#*$'\n'}" "$range" || exit 2
else
  # Could not rebuild (new file, or old_string absent -- the Edit will fail on
  # its own). Fall back to the conservative reading: the fragment as prose.
  checks_language "$rel" "$new" || exit 2
fi
exit 0
