#!/usr/bin/env bash
CASE_DESC="the tick shows every role only the states from KIT_QUEUES, only inside the sprint"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

for pair in 1:planned 2:rfr 3:rft 4:in-testing 5:backlog; do
  sandbox_ticket "${pair%%:*}" "${pair##*:}"
  KIT_ROLE=product-owner "$BIN/tickets.sh" add-label "${pair%%:*}" sprint:current > /dev/null
done
sandbox_ticket 9 planned                       # not in the sprint

nummern() { KIT_ROLE="$1" "$BIN/tick.sh" 2>&1 | grep -oE '^  #[0-9]+' | tr -d ' #' | sort -n | tr '\n' ' ' | sed 's/ $//'; }
e="$(nummern engineer-a)"; q="$(nummern qa-ruthless)"; t="$(nummern acceptance-tester)"
m="$(nummern merge-gate)"; p="$(nummern product-owner)"; w="$(nummern watchdog)"

errors=""
[ "$e" = "1" ] || errors="$errors engineer-a='$e'"
[ "$q" = "2" ] || errors="$errors qa-ruthless='$q'"
[ "$t" = "3" ] || errors="$errors acceptance-tester='$t'"
[ "$m" = "4" ] || errors="$errors merge-gate='$m'"
[ "$p" = "1 2 3 4 5" ] || errors="$errors product-owner='$p'"
[ -z "$w" ] || errors="$errors watchdog='$w'"

observe "engineer-a [$e] · qa-ruthless [$q] · acceptance-tester [$t] · merge-gate [$m] · product-owner [$p] · watchdog [$w] · #9 outside the sprint nowhere${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
