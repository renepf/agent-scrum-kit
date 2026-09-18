#!/usr/bin/env bash
CASE_DESC="claude-code: the session id from the registry of the host process first, then CLAUDE_CODE_SESSION_ID, otherwise a failure"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
A="$KIT_ROOT/adapters/claude-code/session-id.sh"
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
errors=""
printf '{"pid":4242,"sessionId":"after-clear-new"}' > "$D/4242.json"
a="$(env -u KIT_SESSION_ID KIT_HOST_PID=4242 KIT_CLAUDE_SESSIONS_DIR="$D" CLAUDE_CODE_SESSION_ID=before-clear-old "$A" 2>&1)"
[ "$a" = "after-clear-new" ] || errors="$errors registry-not-first:'$a'"
b="$(env -u KIT_SESSION_ID KIT_HOST_PID=5353 KIT_CLAUDE_SESSIONS_DIR="$D" CLAUDE_CODE_SESSION_ID=only-env "$A" 2>&1)"
[ "$b" = "only-env" ] || errors="$errors fallback-env:'$b'"
c="$(env -u KIT_SESSION_ID -u CLAUDE_CODE_SESSION_ID KIT_HOST_PID=5353 KIT_CLAUDE_SESSIONS_DIR="$D" "$A" 2>&1)"; rc=$?
[ "$rc" != 0 ] || errors="$errors without-a-source-exit0:'$c'"
case "$c" in *"do not guess"*) ;; *) errors="$errors message" ;; esac
observe "the registry 'after-clear-new' beats the env 'before-clear-old' · without the registry → env · without either → exit $rc${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
