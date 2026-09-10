#!/usr/bin/env bash
CASE_DESC="der Tick zeigt jeder Rolle nur die Zustaende aus KIT_QUEUES, nur im Sprint"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

for pair in 1:planned 2:rfr 3:rft 4:in-testing 5:backlog; do
  sandbox_ticket "${pair%%:*}" "${pair##*:}"
  KIT_ROLE=product-owner "$BIN/tickets.sh" add-label "${pair%%:*}" sprint:current > /dev/null
done
sandbox_ticket 9 planned                       # nicht im Sprint

nummern() { KIT_ROLE="$1" "$BIN/tick.sh" 2>&1 | grep -oE '^  #[0-9]+' | tr -d ' #' | sort -n | tr '\n' ' ' | sed 's/ $//'; }
e="$(nummern engineer-a)"; q="$(nummern qa-ruthless)"; t="$(nummern acceptance-tester)"
m="$(nummern merge-gate)"; p="$(nummern product-owner)"; w="$(nummern watchdog)"

fehler=""
[ "$e" = "1" ] || fehler="$fehler engineer-a='$e'"
[ "$q" = "2" ] || fehler="$fehler qa-ruthless='$q'"
[ "$t" = "3" ] || fehler="$fehler acceptance-tester='$t'"
[ "$m" = "4" ] || fehler="$fehler merge-gate='$m'"
[ "$p" = "1 2 3 4 5" ] || fehler="$fehler product-owner='$p'"
[ -z "$w" ] || fehler="$fehler watchdog='$w'"

observe "engineer-a [$e] · qa-ruthless [$q] · acceptance-tester [$t] · merge-gate [$m] · product-owner [$p] · watchdog [$w] · #9 ausserhalb des Sprints nirgends${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
