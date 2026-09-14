#!/usr/bin/env bash
CASE_DESC="neun Rollen registrieren sich gleichzeitig: roster.md hat danach neun Zeilen mit den richtigen Session-IDs"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill $PIDS 2>/dev/null; sandbox_cleanup' EXIT
SPRINT="$(sandbox_sprint)"; rm -f "$SPRINT/roster.md"
ROLES="product-owner simplicity-reviewer watchdog engineer-a engineer-b qa-ruthless security-engineer acceptance-tester merge-gate"
# Anlass: Starttest 2026-09-14 — neun echte Sessions, roster.md hatte danach 4 Zeilen.
PIDS=""
for r in $ROLES; do sleep 300 & PIDS="$PIDS $!"; done
set -- $PIDS
REG=""
for r in $ROLES; do
  ( KIT_ROLE="$r" KIT_SESSION_ID="sid-$r" KIT_HOST_PID="$1" "$BIN/register.sh" > /dev/null 2>&1 ) &
  REG="$REG $!"
  shift
done
# Nur auf die Registrierungen warten — ein nacktes "wait" wartet auch auf die sleep-Platzhalter.
wait $REG
zeilen="$(grep -c '^| 2' "$SPRINT/roster.md" 2>/dev/null || echo 0)"
falsch=""
for r in $ROLES; do grep -q "| $r | sid-$r |" "$SPRINT/roster.md" || falsch="$falsch $r"; done
observe "roster.md: $zeilen/9 Zeilen${falsch:+ · fehlend:$falsch}"
echo "BEOBACHTET: $OBSERVED"
[ "$zeilen" = 9 ] && [ -z "$falsch" ]
