#!/usr/bin/env bash
CASE_DESC="Rueckwaertskante aus in-review und in-testing: zurueck an den urspruenglichen Engineer, volle Schleife erneut"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

fehler=""; befund=""; n0=200
for fall in "in-review:qa-ruthless" "in-testing:acceptance-tester"; do
  pz="${fall%%:*}"; pruefer="${fall##*:}"; n=$((n0 += 1))
  # PR-Nummer je Ticket eindeutig — zwei Tickets am selben PR wuerden einander die Verdicts leihen.
  sandbox_issue "$n" "{\"pr\":{\"number\":$n,\"head\":\"feedbeef00\",\"comments\":[],\"checks\":\"pass\"}}"
  sandbox_plannable "$n"
  KIT_ROLE=product-owner "$BIN/status.sh" "$n" planned x > /dev/null 2>&1
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" in-progress x > /dev/null 2>&1
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rfr x > /dev/null 2>&1
  KIT_ROLE=qa-ruthless "$BIN/status.sh" "$n" in-review x > /dev/null 2>&1
  if [ "$pz" = "in-testing" ]; then
    for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment "$n" "$v — HEAD \`feedbeef\`"; done
    KIT_ROLE=qa-ruthless "$BIN/status.sh" "$n" rft x > /dev/null 2>&1
    KIT_ROLE=acceptance-tester "$BIN/status.sh" "$n" in-testing x > /dev/null 2>&1
  fi
  KIT_ROLE="$pruefer" "$BIN/status.sh" "$n" in-progress "Fehler gefunden" > /dev/null 2>&1 || { fehler="$fehler $pz:zurueck-abgelehnt"; continue; }
  nach_rueck="$(sandbox_labels "$n")"
  case "$nach_rueck" in *"owner:engineer-b"*"status:in-progress"*) ;; *) fehler="$fehler $pz:owner='$nach_rueck'" ;; esac
  # dieselbe Schleife erneut, ohne Abkuerzung — und die Abkuerzung selbst muss scheitern
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rft x > /dev/null 2>&1 && fehler="$fehler $pz:abkuerzung-rft-durchgelassen"
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rfr erneut > /dev/null 2>&1 || fehler="$fehler $pz:reloop-rfr"
  KIT_ROLE=security-engineer "$BIN/status.sh" "$n" in-review erneut > /dev/null 2>&1 || fehler="$fehler $pz:reloop-in-review"
  befund="$befund ${pz} → in-progress (owner:engineer-b) → rfr → in-review;"
done
observe "${befund}${fehler:+ FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
