#!/usr/bin/env bash
CASE_DESC="the role survives a context reset through the anchor on the host process, without KIT_ROLE"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'rm -rf "$KIT_ROOT/.pid-roles/$KIT_HOST_PID"; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
errors=""
# A tick with a role sets the anchor.
KIT_ROLE=engineer-b "$BIN/tick.sh" > /dev/null 2>&1 || errors="$errors first-tick"
anchor="$(cat "$KIT_ROOT/.pid-roles/$KIT_HOST_PID" 2>/dev/null)"
[ "$anchor" = "engineer-b" ] || errors="$errors anchor='$anchor'"
# "Reset": a new session id, KIT_ROLE no longer set, the same host process.
out="$(env -u KIT_ROLE KIT_SESSION_ID=nach-reset "$BIN/tick.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] || errors="$errors tick-without-KIT_ROLE-exit-$rc"
grep -q '| engineer-b | nach-reset |' "$SANDBOX/sprints/S-001-eval/roster.md" || errors="$errors new-session-not-registered-as-engineer-b"
# A foreign host process without an anchor: no guessed role.
out2="$(env -u KIT_ROLE KIT_HOST_PID=999999 "$BIN/tick.sh" 2>&1)"; rc2=$?
[ "$rc2" != 0 ] || errors="$errors foreign-process-got-a-role"
case "$out2" in *"role unknown"*) ;; *) errors="$errors no-clear-message" ;; esac
observe "the anchor after the tick: $anchor · without KIT_ROLE registered again as engineer-b: $(grep -c '| engineer-b | nach-reset |' "$SANDBOX/sprints/S-001-eval/roster.md") · a foreign process: exit $rc2, 'role unknown'${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
