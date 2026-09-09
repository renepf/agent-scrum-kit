#!/usr/bin/env bash
CASE_DESC="bekannte Transkripte ergeben exakt den erwarteten Kontextwert"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

{
  printf '# roster\n\n| Zeit | Rolle | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | sess-quiet | test-fixture |\n'
  printf '| 2026-01-01 00:00 | engineer-b | sess-warn | test-fixture |\n'
  printf '| 2026-01-01 00:00 | qa-ruthless | sess-stop | test-fixture |\n'
} > "$SPRINT/roster.md"

KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1

wert() { grep "| $1 |" "$SPRINT/budget.md" | awk -F'|' '{gsub(/ /,"",$4); print $4}'; }
q="$(wert engineer-a)"; w="$(wert engineer-b)"; s="$(wert qa-ruthless)"

observe "engineer-a $q (erwartet 1150) · engineer-b $w (erwartet 260000) · qa-ruthless $s (erwartet 300010)"
echo "BEOBACHTET: $OBSERVED"
[ "$q" = "1150" ] && [ "$w" = "260000" ] && [ "$s" = "300010" ]
