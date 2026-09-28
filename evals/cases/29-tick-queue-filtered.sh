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
# Since the cut of 2026-09-28 an engineer sees five states: planned to build, and rfr, in-review,
# rft, in-testing to review a foreign ticket. Which of them is its own, the gate decides — not the
# queue. requirements-engineer sees only the backlog, the product-owner everything, watchdog nothing.
e="$(nummern engineer-a)"; r="$(nummern requirements-engineer)"
p="$(nummern product-owner)"; w="$(nummern watchdog)"; k="$(nummern kit-maintainer)"

errors=""
[ "$e" = "1 2 3 4" ] || errors="$errors engineer-a='$e'"
[ "$r" = "5" ] || errors="$errors requirements-engineer='$r'"
[ "$p" = "1 2 3 4 5" ] || errors="$errors product-owner='$p'"
[ -z "$w" ] || errors="$errors watchdog='$w'"
[ -z "$k" ] || errors="$errors kit-maintainer='$k'"

observe "engineer-a [$e] · requirements-engineer [$r] · product-owner [$p] · watchdog [$w] · kit-maintainer [$k] · #9 outside the sprint nowhere${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
