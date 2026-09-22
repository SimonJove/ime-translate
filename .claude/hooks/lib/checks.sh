#!/usr/bin/env bash
# The ONLY implementation of the hard checks (spike gate, Lua invariants,
# secrets, language). Both Claude's PreToolUse
# hooks and .githooks/pre-commit source this file. Never write a second copy:
# two copies drift, and the drift is always in the direction of the git side
# being looser — i.e. "Claude gets blocked, my own hand edit slips through".
#
# Contract for every checks_* function:
#   args:  <path relative to repo root> <file content>
#   hit    -> explain in plain words on stderr, return 1
#   clean  -> return 0
# They never exit; the caller decides (hook: exit 2, pre-commit: tally then
# exit 1).
#
# The caller must set PROJECT_ROOT first.

# --- Gate: no implementation code before S1/S3/S11 conclude (design §3.5) ---
#
# Written only in a document, this rule loses to "let me just write json.lua,
# it's needed either way". Then the spike comes back saying S1 does not hold and
# two thousand lines of Lua plus their tests are void. So it is mechanical.
checks_gate() {
  local rel="$1"
  case "$rel" in rime/*|tests/*) ;; *) return 0 ;; esac

  # The gate belongs to whichever feature owns rime/ and tests/ -- today that is
  # 001, and any later feature that touches them inherits the same rule. Reading
  # every feature and refusing unless ALL of them pass fails closed: adding a
  # feature can never accidentally unlock the tree.
  local gate="" p
  shopt -s nullglob
  for p in "$PROJECT_ROOT"/docs/features/*/progress.json; do
    local g
    if command -v jq >/dev/null 2>&1; then
      g=$(jq -r 'if .gate then .gate.status else "pass" end' "$p")
    else
      g=$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\(pass\|fail\|unverified\)".*/\1/p' "$p" | head -1)
    fi
    case "$g" in
      fail) gate=fail; break ;;
      pass) [[ -z "$gate" ]] && gate=pass ;;
      *)    gate=unverified ;;
    esac
  done
  shopt -u nullglob
  [[ -z "$gate" ]] && return 0        # no feature ledger at all: foreign tree, step aside
  [[ "$gate" == "pass" ]] && return 0

  if [[ "$gate" == "fail" ]]; then
    cat >&2 <<EOF
Gate S1/S3/S11 is falsified — ${rel} does not get written.

If S1 or S3 was falsified, Plan A' does not exist. design §3.5: return to design
and re-review, evaluating Plan B' (Lua-owned draft) first. Do not jump to C'
(fork Squirrel), and do not quietly amend the design to keep going.

If S11 was falsified, design §6.1-§6.2 go back to design review before any
implementation continues; Plan A' itself may still stand.
EOF
  else
    cat >&2 <<EOF
Gate S1/S3/S11 unverified — refusing to write ${rel}.

Task 1 (Phase 0 spike) has not concluded. If either S1 (fluid_editor does not
commit segment selections to the app) or S3 (engine:commit_text accepts
arbitrary text) is falsified, Plan A' does not exist and the implementation code
written now is void in its entirety. If S11 (the Enter -> preview -> Enter loop
closes) is falsified, design §6.1-§6.2 are redesigned before anything is built
on them.

Run Task 1 first:  ./scripts/progress.sh show 1
Once it concludes: ./scripts/progress.sh gate pass    (or gate fail)

docs/ and .claude/ are not gated; write the spike report as normal.
EOF
  fi
  return 1
}

# --- Two Lua invariants ---
checks_lua_invariants() {
  local rel="$1" body="$2" base fail=0
  [[ "$rel" == *.lua ]] || return 0
  [[ -z "$body" ]] && return 0
  base=$(basename "$rel")

  # 1. One commit exit (design §3.1). Letting a candidate carry both display and
  #    commit is the common root of both fatal defects in the original Plan A.
  if [[ "$base" != "ime_translate_processor.lua" ]]; then
    if printf '%s' "$body" | grep -qE '(engine|env\.engine)[:.]commit_text'; then
      cat >&2 <<EOF
${base} contains commit_text — the commit exit must be unique.

design §3.1: the display is the prompt, which nothing commits; the processor
alone owns committing. To commit, go back to ime_translate_processor.lua.
EOF
      fail=1
    fi
  fi

  # 2. %q must not build shell commands (design §7.3).
  #    Only flag a line carrying BOTH %q and a shell command: in tests
  #    ("got %q"):format(...) is ordinary display formatting, and a hook that
  #    cries wolf gets switched off, which is worse than no hook at all.
  local offending
  offending=$(printf '%s' "$body" | grep -nE '%q' | grep -E 'popen|os\.execute|curl|security |/bin/sh|cmd' || true)
  if [[ -n "$offending" ]]; then
    cat >&2 <<EOF
${base} builds a shell command with %q — use json.shq instead.

${offending}

string.format("%q", s) is Lua literal escaping: it yields double quotes, inside
which \$() and backticks still expand in a shell. json.shq uses POSIX single
quotes and is the project's only shell-escaping entry point. The API key travels
exactly this path.
EOF
    fail=1
  fi
  return $fail
}

# A hook test suite must contain the very things the hooks refuse -- a
# real-shaped key, a Chinese comment -- or it cannot prove the check fires. This
# is the one sanctioned place for that, and the exemption is scoped to those two
# directories and nothing else. Every case that uses it also asserts, alongside,
# that a neighbouring path is still refused.
#
# (Hit three times while building the harness: first by check-secrets on
# .claude/hooks/tests, then by check-language on the same file, then by
# check-secrets on .githooks/tests. Hence one predicate instead of three
# scattered cases.)
checks_is_hook_fixture() {
  case "$1" in
    .claude/hooks/tests/*|.githooks/tests/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Secrets red line (design §7.3) ---
#
# This project's leak path is shorter than most: config is installed into
# ~/Library/Rime/, a directory Rime rescans wholesale on "Redeploy" and that
# people routinely push to GitHub as config sync. Written there once is public.
checks_secrets() {
  local rel="$1" body="$2" fail=0 hit masked
  [[ -z "$body" ]] && return 0

  # Hook fixtures must look like real keys or they cannot prove the detector
  # works. The exemption only applies to Edit/Write and pre-commit: at the Bash
  # layer there is no path context, so rel is empty and editing a fixture with a
  # heredoc is still refused. Use Edit/Write for those files.
  checks_is_hook_fixture "$rel" && return 0

  # Only prefixes with an unambiguous real shape, so docs can still write sk-xxx.
  hit=$(printf '%s' "$body" | grep -oE 'sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}' | head -3 || true)
  if [[ -n "$hit" ]]; then
    masked=$(printf '%s' "$hit" | sed -E 's/(sk-[a-z-]*)[A-Za-z0-9_-]+/\1…/')
    cat >&2 <<EOF
${rel:-<command>} contains something shaped like a real API key:

${masked}

Secrets never enter the repo, and never enter ~/Library/Rime/ (design §7.3).
The correct path — run once yourself, in your own terminal, not via an agent:
  security add-generic-password -s ime-translate -a <backend> -w <your-key>
Config then holds only: api_key_account: <backend>
EOF
    fail=1
  fi

  if [[ "$rel" == *.yaml || "$rel" == *.yml ]]; then
    if printf '%s' "$body" | grep -qE '^[[:space:]]*#?[[:space:]]*api_key[[:space:]]*:' \
       && ! printf '%s' "$body" | grep -qE '^[[:space:]]*#?[[:space:]]*api_key[[:space:]]*:.*<'; then
      cat >&2 <<EOF
$(basename "$rel") contains api_key: — config may only hold api_key_account:.

design §7.3, §9: what appears in config is the Keychain account name, never the
secret itself.
EOF
      fail=1
    fi
  fi
  return $fail
}

# --- English-only, with three narrow data exceptions (rules/core.md) ---
#
# The whole repo was translated to English by hand on 2026-09-19. A rule that
# lives only in prose decays on the next session that writes a Chinese comment,
# so it is mechanical -- the same reasoning as every other check here.
#
# What is legitimately Chinese is *data*, not prose, and it is bounded:
#   1. whole files that exist to hold it   -> path exemptions below
#   2. quoted inside English documentation -> must sit in a fenced code block
#      or inline backticks. That is also semantically right: it IS data being
#      quoted, so it belongs in code formatting.
# Anything else -- a Chinese comment, a Chinese sentence in prose -- is refused.
#
# Deliberately NOT a git-diff scan: this reads whole staged content so fenced
# code blocks can be tracked reliably, which a +/- line view cannot do.
#
# Optional third argument "<first>:<last>": report only offending lines inside
# that range. Fences are still tracked from line 1 -- that is the point. An Edit
# hook passes the lines its replacement occupies, so a fragment that sits inside
# a fence is judged as fenced, and Chinese elsewhere in the file is left to
# pre-commit rather than blamed on an unrelated edit. No range: the whole file.
checks_language() {
  local rel="$1" body="$2" range="${3:-}"
  [[ -z "$body" ]] && return 0

  # Files whose entire job is holding Chinese data.
  case "$rel" in
    eval/*) return 0 ;;                                  # evaluation sentence set
    rime/lua/ime_translate/state.lua) return 0 ;;        # the eight error strings
    rime/lua/ime_translate/config.lua) return 0 ;;       # the translation prompt
    rime/*.schema.yaml) return 0 ;;                      # schema name shown in the macOS menu
    .claude/hooks/lib/checks.sh) return 0 ;;             # this file documents the rule
  esac
  checks_is_hook_fixture "$rel" && return 0   # fixtures must contain Chinese to test this

  local md=0; [[ "$rel" == *.md ]] && md=1
  # tests/*.lua: a string literal is test data (rules/core.md lists Chinese test
  # sentences as data); a comment is prose and is still checked.
  local luatest=0; [[ "$rel" == tests/*.lua ]] && luatest=1
  local offending
  # perl, not awk: macOS awk does not match the CJK byte ranges reliably, and
  # that failure is silent -- the check simply passes everything. Caught on
  # 2026-09-19 only because run-hook-tests.sh asserts the blocking cases.
  offending=$(printf '%s' "$body" | MD="$md" LUATEST="$luatest" RANGE="$range" perl -CSD -ne '
    BEGIN { $fence = 0; $md = $ENV{MD}; $luatest = $ENV{LUATEST};
            ($lo, $hi) = $ENV{RANGE} =~ /^(\d+):(\d+)$/ ? ($1, $2) : (0, 0) }
    # A fence may sit inside a blockquote ("> ```yaml"); it is a fence all the same.
    if ($md && /^\s*(?:>\s*)*```/) { $fence = !$fence; next }
    next if $md && $fence;
    next if $hi && ($. < $lo || $. > $hi);
    my $line = $_;
    # tests/*.lua: tokenise left to right so a "--" inside a string is not a
    # comment and a quote inside a comment is not a string. Only the comment
    # and code survive to the Han check. A long string ([[...]]) is not
    # recognised, so Chinese in one is still refused -- failing closed.
    if ($luatest) {
      my $kept = "";
      while ($line =~ /\G(?:("(?:\\.|[^"\\\n])*")|(\x27(?:\\.|[^\x27\\\n])*\x27)|(--.*)|(.))/gs) {
        $kept .= defined $3 ? $3 : defined $4 ? $4 : "";
      }
      $line = $kept;
    }
    $line =~ s/`[^`]*`//g;          # inline code spans hold quoted data
    if ($line =~ /\p{Han}/) { my $s = $_; chomp $s; printf "  %d: %.88s\n", $., $s }
  ')
  [[ -z "$offending" ]] && return 0

  cat >&2 <<EOF
$(basename "$rel") has Chinese outside the permitted forms:

${offending}
Project files are English (rules/core.md). Chinese is allowed only as data:
  - in a file that exists to hold it (eval/, state.lua, config.lua, *.schema.yaml)
  - quoted inside a fenced code block, or inline backticks, in a .md file
  - inside a string literal in tests/*.lua (test data; comments still count)

A Chinese comment or a Chinese sentence in prose is not data. Translate it. If
you are quoting one of the product's own Chinese strings, put it in backticks.
EOF
  return 1
}

# Convert an absolute path to repo-relative; return non-zero when outside the
# repo so the caller can skip it.
checks_relpath() {
  local file="$1"
  case "$file" in
    /*) [[ "$file" == "$PROJECT_ROOT"/* ]] || return 1; printf '%s' "${file#"$PROJECT_ROOT"/}" ;;
    *)  printf '%s' "$file" ;;
  esac
}
