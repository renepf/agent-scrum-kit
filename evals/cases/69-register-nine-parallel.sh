#!/usr/bin/env bash
CASE_DESC="nine roles register at the same time: roster.md then has nine lines with the right session ids"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill $PIDS 2>/dev/null; sandbox_cleanup' EXIT
SPRINT="$(sandbox_sprint)"; rm -f "$SPRINT/roster.md"
ROLES="product-owner simplicity-reviewer watchdog engineer-a engineer-b qa-ruthless security-engineer acceptance-tester merge-gate"
# The reason: the start test of 2026-09-14 — nine real sessions, roster.md then had 4 lines.
PIDS=""
for r in $ROLES; do sleep 300 & PIDS="$PIDS $!"; done
set -- $PIDS
REG=""
for r in $ROLES; do
  ( KIT_ROLE="$r" KIT_SESSION_ID="sid-$r" KIT_HOST_PID="$1" "$BIN/register.sh" > /dev/null 2>&1 ) &
  REG="$REG $!"
  shift
done
# Wait only for the registrations — a bare "wait" would also wait for the sleep placeholders.
wait $REG
lines="$(grep -c '^| 2' "$SPRINT/roster.md" 2>/dev/null || echo 0)"
missing=""
for r in $ROLES; do grep -q "| $r | sid-$r |" "$SPRINT/roster.md" || missing="$missing $r"; done
observe "roster.md: $lines/9 lines${missing:+ · missing:$missing}"
echo "OBSERVED: $OBSERVED"
[ "$lines" = 9 ] && [ -z "$missing" ]
