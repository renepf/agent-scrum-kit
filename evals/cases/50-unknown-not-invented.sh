#!/usr/bin/env bash
CASE_DESC="unsettled adapters carry UNKNOWN and no invented start command"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

SENTENCE="UNKNOWN — ask the owner for the start command, the session id and the tool names"
errors=""
for host in hermes; do
  R="$KIT_ROOT/adapters/$host/README.md"
  [ -f "$R" ] || { errors="$errors $host:no-README"; continue; }
  n="$(grep -c "$SENTENCE" "$R" || true)"
  [ "$n" -ge 3 ] || errors="$errors $host:UNKNOWN-sentence only ${n}x"
  # A code block with a start command would be an invention.
  if grep -qE '^\s*(\$ )?[a-z][a-z0-9-]+ +(--?[a-z]|run|start|chat)' "$R"; then
    errors="$errors $host:looks-like-an-invented-command"
  fi
  # Die Skripte duerfen scheitern, aber nie etwas erfinden.
  "$KIT_ROOT/adapters/$host/session-id.sh" > /dev/null 2>&1 && errors="$errors $host:session-id.sh-returns-something"
done

observe "hermes: the UNKNOWN sentence is there, no start command, session-id.sh fails${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
