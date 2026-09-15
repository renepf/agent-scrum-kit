#!/usr/bin/env bash
CASE_DESC="done und Merge: product-owner hat das letzte Wort, CI wird frisch gemessen"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 3 '{"labels":["status:in-testing","owner:acceptance-tester"],"pr":{"number":30,"head":"0badc0de77","comments":[],"checks":"pending","state":"OPEN"}}'
# Gates gruen von Anfang an: dieser Fall prueft Freigaben und CI, nicht die Gates (Fall 95).
sandbox_gates_green 3
m() { KIT_ROLE="$1" "$BIN/merge.sh" 3 2>&1; }
fehler=""

o1="$(m engineer-a)";   case "$o1" in *"mergen darf nur"*) ;; *) fehler="$fehler engineer-durfte" ;; esac
o2="$(m product-owner)"; case "$o2" in *"MERGE-GATE OK"*) ;; *) fehler="$fehler PO-ohne-Gate" ;; esac
sandbox_pr_comment 3 'MERGE-GATE OK — HEAD `0badc0de`'
o3="$(m merge-gate)";    case "$o3" in *"PO OK"*) ;; *) fehler="$fehler Gate-ohne-PO-OK" ;; esac
o4="$(KIT_ROLE=merge-gate "$BIN/status.sh" 3 done x 2>&1)"; case "$o4" in *"letzte Wort"*) ;; *) fehler="$fehler done-ohne-PO-OK" ;; esac
o5="$(m product-owner)"; case "$o5" in *"CI"*"nicht gruen"*) ;; *) fehler="$fehler pending-CI-durch" ;; esac
sandbox_issue 3 '{"pr":{"number":30,"head":"0badc0de77","comments":["MERGE-GATE OK — HEAD `0badc0de`","PO OK — HEAD `0badc0de`"],"checks":"pass","state":"OPEN"}}'
o6="$(m merge-gate)";    case "$o6" in *"in-testing → done"*) ;; *) fehler="$fehler Gate-mit-PO-OK-abgelehnt:'$(echo "$o6" | tail -1)'" ;; esac

observe "engineer → abgelehnt · PO ohne MERGE-GATE OK → abgelehnt · merge-gate ohne PO OK → abgelehnt (merge und done) · CI pending → abgelehnt · merge-gate mit PO OK + CI gruen → $(echo "$o6" | grep -o 'in-testing → done' || echo '?')${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
