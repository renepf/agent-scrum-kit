#!/usr/bin/env bash
CASE_DESC="Rueckwaertskante aus jedem Pruefzustand fuehrt auf in-progress, volle Schleife laeuft erneut"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=qa-ruthless

fails=""; nr=1000
for pruefzustand in in-review in-testing; do
  nr=$((nr + 1))
  sandbox_ticket "$nr" "$pruefzustand"
  "$BIN/status.sh" "$nr" in-progress "Fehler gefunden" > /dev/null 2>&1 \
    || { fails="$fails $pruefzustand>in-progress"; continue; }
  # volle Schleife erneut, ohne Abkuerzung
  for st in rfr in-review rft in-testing; do
    "$BIN/status.sh" "$nr" "$st" "erneut" > /dev/null 2>&1 \
      || { fails="$fails $pruefzustand:reloop:$st"; break; }
  done
  ist="$("$BIN/tickets.sh" labels "$nr" | grep '^status:' | sed 's/status://')"
  [ "$ist" = "in-testing" ] || fails="$fails $pruefzustand:endstand=$ist"
done
observe "$([ -z "$fails" ] && echo 'in-review und in-testing: zurueck auf in-progress, Schleife rfr>in-review>rft>in-testing erneut durchlaufen' || echo "Fehler:$fails")"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fails" ]
