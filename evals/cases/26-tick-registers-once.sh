#!/usr/bin/env bash
CASE_DESC="the tick registers once and again after a reset with a new session id"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
export KIT_ROLE=watchdog

KIT_SESSION_ID=alt "$BIN/tick.sh" > /dev/null 2>&1
KIT_SESSION_ID=alt "$BIN/tick.sh" > /dev/null 2>&1
after_two="$(grep -c '| watchdog |' "$SPRINT/roster.md")"
KIT_SESSION_ID=neu "$BIN/tick.sh" > /dev/null 2>&1
after_reset="$(grep -c '| watchdog |' "$SPRINT/roster.md")"
sid="$(grep '| watchdog |' "$SPRINT/roster.md" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"

observe "after two ticks $after_two line · after a reset $after_reset line with session '$sid'"
echo "OBSERVED: $OBSERVED"
[ "$after_two" = 1 ] && [ "$after_reset" = 1 ] && [ "$sid" = "neu" ]
