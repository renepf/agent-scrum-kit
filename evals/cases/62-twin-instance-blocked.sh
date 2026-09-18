#!/usr/bin/env bash
CASE_DESC="the twin lock: a second living instance of the same role is refused, a dead one is not"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$TWIN" 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null

sleep 300 & TWIN=$!          # the "first" instance: a living process
errors=""

o1="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-1 KIT_HOST_PID="$TWIN" "$BIN/register.sh" 2>&1)" || errors="$errors first-instance-refused"
o2="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-1 KIT_HOST_PID="$TWIN" "$BIN/register.sh" 2>&1)" || errors="$errors same-instance-refused-again"
o3="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-1 KIT_HOST_PID=$$ "$BIN/tick.sh" 2>&1)"; rc3=$?
case "$o3" in *"second instance"*) ;; *) errors="$errors twin-with-the-same-session-let-through" ;; esac
[ "$rc3" != 0 ] || errors="$errors tick-exit-0-despite-a-twin"
o4="$(KIT_ROLE=engineer-b KIT_SESSION_ID=sess-2 KIT_HOST_PID=$$ "$BIN/register.sh" 2>&1)" || errors="$errors other-role-refused"

kill "$TWIN"; wait "$TWIN" 2>/dev/null
o5="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-3 KIT_HOST_PID=$$ "$BIN/register.sh" 2>&1)" || errors="$errors dead-instance-blocks"
lines="$(grep -c '| engineer-a |' "$SANDBOX/sprints/S-001-eval/roster.md")"
[ "$lines" = 1 ] || errors="$errors roster-has-$lines-lines-for-engineer-a"

observe "the same instance again: ok · a twin (another PID, the same session): refused, tick exit $rc3 · another role: ok · after the first instance died: taken over, roster 1 line${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
