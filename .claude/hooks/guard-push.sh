#!/usr/bin/env bash
# PreToolUse(Bash): refuse a `git push` that the user has not authorised.
#
# CLAUDE.md says "Never commit or push unprompted." That was prose, so it held
# only while whoever typed the command remembered it. cloudoverture's equivalent
# guard exists because exactly that failed there on 2026-09-17: a campaign was
# pushed to main right after the user had been asked "shall I push, or will
# you?" and had not answered.
#
# SCOPE, stated honestly: this repo has NO remote today, so the guard is dormant
# -- it costs nothing and does nothing until a remote is added. It is here so
# the rule is already mechanical on the day that changes, rather than being
# remembered afterwards.
#
# NOT blocked: `git commit`. This project works directly on main and the plan
# has every task end in a commit, so a commit gate would block the normal
# workflow. Publishing is the irreversible step; committing locally is not.
#
# SCOPE: a Claude Code hook constrains the agent's Bash calls only. A human
# typing in their own terminal is unaffected, by design.
#
# FAIL CLOSED: if a push is present and authorisation cannot be established,
# block. A wrong block costs one round trip; a wrong pass publishes.

input=$(cat)
# The command arrives embedded in JSON, so quoted bodies are escaped.
norm="${input//\\/}"

case "$norm" in *"git push"*) ;; *) exit 0 ;; esac

# The user authorises a push by including this token in what they asked for,
# which the agent then carries in the command as a trailing comment:
#   git push origin main   # authorized-by-user
case "$norm" in *"authorized-by-user"*) exit 0 ;; esac

cat >&2 <<'EOF'
Refusing `git push`: the user has not authorised it.

CLAUDE.md: never commit or push unprompted. Ask first, in plain words, and say
what would be published.

Once they have said yes, carry their authorisation in the command:
  git push <remote> <branch>   # authorized-by-user

(A human running git push in their own terminal is unaffected by this hook.)
EOF
exit 2
