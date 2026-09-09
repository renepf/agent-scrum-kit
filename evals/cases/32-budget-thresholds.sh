#!/usr/bin/env bash
CASE_DESC="die Schwellen loesen an der richtigen Stelle aus, Grenzwert eingeschlossen"
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
lage() { grep "| $1 |" "$SPRINT/budget.md" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}'; }

lq="$(lage engineer-a)"; lw="$(lage engineer-b)"; ls_="$(lage qa-ruthless)"
stop_zeile="$(grep '^STOP ' "$SPRINT/budget.md" | tr '\n' ' ')"

fehler=""
[ "$lq" = "ok" ] || fehler="$fehler engineer-a=$lq"
case "$lw" in Warnung*) ;; *) fehler="$fehler engineer-b=$lw" ;; esac
case "$ls_" in *STOPP*) ;; *) fehler="$fehler qa-ruthless=$ls_" ;; esac
[ "$stop_zeile" = "STOP qa-ruthless " ] || fehler="$fehler flag='$stop_zeile'"

observe "1150→ok · 260000→Warnung · 300010→STOPP · Flagzeile '$(echo "$stop_zeile" | sed 's/ $//')'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
