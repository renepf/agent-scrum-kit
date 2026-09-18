#!/usr/bin/env bash
CASE_DESC="the adapter never guesses the session id from the youngest transcript file"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

FAKEHOME="$(mktemp -d)"; trap 'rm -rf "$FAKEHOME"' EXIT
mkdir -p "$FAKEHOME/.claude/projects/p"
touch "$FAKEHOME/.claude/projects/p/foreign-session.jsonl"   # the youngest file belongs to somebody else
A="$KIT_ROOT/adapters/claude-code/session-id.sh"

without="$(HOME="$FAKEHOME" KIT_SESSION_ID= CLAUDE_CODE_SESSION_ID= "$A" 2>/dev/null)"; rc_without=$?
with="$(HOME="$FAKEHOME" KIT_SESSION_ID= CLAUDE_CODE_SESSION_ID=own-session "$A" 2>/dev/null)"; rc_mit=$?

errors=""
[ "$rc_without" != 0 ] || errors="$errors without-the-variable-no-abort"
[ "$without" != "foreign-session" ] || errors="$errors guessed-the-foreign-session"
[ "$with" = "own-session" ] || errors="$errors with-the-variable='$with'"

observe "without the variable: exit $rc_without, output '${without}' · with CLAUDE_CODE_SESSION_ID: '$with' · the youngest foreign file ignored${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
