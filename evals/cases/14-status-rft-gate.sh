#!/usr/bin/env bash
CASE_DESC="rft verlangt QA, SIMPLICITY und SECURITY PASS fuer den AKTUELLEN HEAD; ein Push entwertet alte Verdicts"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 5 '{"labels":["status:in-review","owner:qa-ruthless"],"pr":{"number":50,"head":"11111111aaaa","comments":[]}}'
try() { KIT_ROLE=qa-ruthless "$BIN/status.sh" 5 rft x 2>&1; }

fehler=""
sandbox_pr_comment 5 'QA PASS — HEAD `11111111`'
sandbox_pr_comment 5 'SIMPLICITY PASS — HEAD `11111111`'
o1="$(try)"; case "$o1" in *"fehlt"*"SECURITY PASS"*) ;; *) fehler="$fehler fehlendes-Verdict-nicht-erkannt" ;; esac

sandbox_pr_comment 5 'SECURITY PASS — HEAD `11111111`'
sandbox_issue 5 '{"pr":{"number":50,"head":"22222222bbbb","comments":["QA PASS — HEAD `11111111`","SIMPLICITY PASS — HEAD `11111111`","SECURITY PASS — HEAD `11111111`"]}}'
o2="$(try)"; case "$o2" in *"fehlt fuer HEAD 22222222"*) ;; *) fehler="$fehler alter-HEAD-durchgelassen" ;; esac

sandbox_pr_comment 5 'Nebenbei: QA PASS waere schoen — HEAD `22222222`'
o3="$(try)"; case "$o3" in *"fehlt"*"QA PASS"*) ;; *) fehler="$fehler Verdict-nicht-in-erster-Zeile-akzeptiert" ;; esac

for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 5 "$v — HEAD \`22222222\`, geprueft"; done
o4="$(try)"; case "$o4" in *"in-review → rft"*) ;; *) fehler="$fehler gueltige-Verdicts-abgelehnt:'$o4'" ;; esac

observe "2 von 3 → abgelehnt · alle 3 fuer alten HEAD → abgelehnt · Verdict mitten im Satz → abgelehnt · alle 3 fuer neuen HEAD → $(echo "$o4" | tail -1)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
