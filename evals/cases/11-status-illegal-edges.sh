#!/usr/bin/env bash
CASE_DESC="jeder unerlaubte Uebergang wird abgelehnt"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=product-owner

# Alle Paare aus den acht Zustaenden, die nicht in protocols/LOOP.md als Kante stehen.
STATES="backlog planned in-progress rfr in-review rft in-testing"
ALLOWED=" backlog>planned planned>in-progress in-progress>rfr rfr>in-review in-review>rft in-review>in-progress rft>in-testing in-testing>in-progress in-testing>done "

nr=100; rejected=0; total=0; leaked=""
for from in $STATES; do
  for to in $STATES done; do
    [ "$from" = "$to" ] && continue
    case "$ALLOWED" in *" $from>$to "*) continue ;; esac
    nr=$((nr + 1)); total=$((total + 1))
    sandbox_ticket "$nr" "$from"
    if "$BIN/status.sh" "$nr" "$to" "eval" > /dev/null 2>&1; then
      leaked="$leaked $from>$to"
    else
      rejected=$((rejected + 1))
    fi
  done
done
observe "$rejected/$total abgelehnt${leaked:+, durchgelassen:$leaked}"
echo "BEOBACHTET: $OBSERVED"
[ "$rejected" = "$total" ] && [ "$total" = 40 ]   # 7 Ausgangszustaende x 7 Ziele - 9 erlaubte Kanten
