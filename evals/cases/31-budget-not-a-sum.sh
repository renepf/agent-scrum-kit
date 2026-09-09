#!/usr/bin/env bash
CASE_DESC="Kontext ist der groesste Turn, nicht die Summe ueber alle Turns"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

# sess-sumtrap: drei Turns zu je 120000. Summe waere 360000 (ueber Stopp),
# der groesste Turn ist 120000 (unauffaellig).
{
  printf '# roster\n\n| Zeit | Rolle | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | sess-sumtrap | test-fixture |\n'
} > "$SPRINT/roster.md"

KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
v="$(grep '| engineer-a |' "$SPRINT/budget.md" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"
lage="$(grep '| engineer-a |' "$SPRINT/budget.md" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')"
flag="$(grep -c '^STOP ' "$SPRINT/budget.md" || true)"

observe "gemessen $v (Summe waere 360000) · Lage '$lage' · Stopp-Flags $flag"
echo "BEOBACHTET: $OBSERVED"
[ "$v" = "120000" ] && [ "$lage" = "ok" ] && [ "$flag" = "0" ]
