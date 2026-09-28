#!/usr/bin/env bash
CASE_DESC="the whole cast registers at the same time: roster.md then has one line per role with the right session ids"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill $PIDS 2>/dev/null; sandbox_cleanup' EXIT
SPRINT="$(sandbox_sprint)"; rm -f "$SPRINT/roster.md"
ROLES="product-owner requirements-engineer watchdog engineer-a engineer-b engineer-c kit-maintainer"
ERWARTET="$(echo "$ROLES" | wc -w | tr -d " ")"
# The reason: the start test of 2026-09-14 — nine real sessions, roster.md then had 4 lines. Nine
# roles became seven on 2026-09-28; what is measured is that not one line is lost, whatever the count.
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
observe "roster.md: $lines/$ERWARTET lines${missing:+ · missing:$missing}"
echo "OBSERVED: $OBSERVED"
[ "$lines" = "$ERWARTET" ] && [ -z "$missing" ]
