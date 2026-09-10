#!/usr/bin/env bash
CASE_DESC="der Tick registriert einmal und nach einem Reset mit neuer Session-ID erneut"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
export KIT_ROLE=watchdog

KIT_SESSION_ID=alt "$BIN/tick.sh" > /dev/null 2>&1
KIT_SESSION_ID=alt "$BIN/tick.sh" > /dev/null 2>&1
nach_zwei="$(grep -c '| watchdog |' "$SPRINT/roster.md")"
KIT_SESSION_ID=neu "$BIN/tick.sh" > /dev/null 2>&1
nach_reset="$(grep -c '| watchdog |' "$SPRINT/roster.md")"
sid="$(grep '| watchdog |' "$SPRINT/roster.md" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"

observe "nach zwei Ticks $nach_zwei Zeile · nach Reset $nach_reset Zeile mit Session '$sid'"
echo "BEOBACHTET: $OBSERVED"
[ "$nach_zwei" = 1 ] && [ "$nach_reset" = 1 ] && [ "$sid" = "neu" ]
