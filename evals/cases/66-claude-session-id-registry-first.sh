#!/usr/bin/env bash
CASE_DESC="claude-code: Session-ID zuerst aus der Registry des Host-Prozesses, dann CLAUDE_CODE_SESSION_ID, sonst Fehlschlag"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
A="$KIT_ROOT/adapters/claude-code/session-id.sh"
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
fehler=""
printf '{"pid":4242,"sessionId":"nach-clear-neu"}' > "$D/4242.json"
a="$(env -u KIT_SESSION_ID KIT_HOST_PID=4242 KIT_CLAUDE_SESSIONS_DIR="$D" CLAUDE_CODE_SESSION_ID=vor-clear-alt "$A" 2>&1)"
[ "$a" = "nach-clear-neu" ] || fehler="$fehler registry-nicht-zuerst:'$a'"
b="$(env -u KIT_SESSION_ID KIT_HOST_PID=5353 KIT_CLAUDE_SESSIONS_DIR="$D" CLAUDE_CODE_SESSION_ID=nur-env "$A" 2>&1)"
[ "$b" = "nur-env" ] || fehler="$fehler rueckfall-env:'$b'"
c="$(env -u KIT_SESSION_ID -u CLAUDE_CODE_SESSION_ID KIT_HOST_PID=5353 KIT_CLAUDE_SESSIONS_DIR="$D" "$A" 2>&1)"; rc=$?
[ "$rc" != 0 ] || fehler="$fehler ohne-quelle-exit0:'$c'"
case "$c" in *"nicht raten"*) ;; *) fehler="$fehler meldung" ;; esac
observe "Registry 'nach-clear-neu' schlaegt Env 'vor-clear-alt' · ohne Registry → Env · ohne beides → Exit $rc${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
