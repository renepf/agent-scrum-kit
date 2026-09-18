#!/usr/bin/env bash
CASE_DESC="done and merge: the product-owner has the last word, CI is measured fresh"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 3 '{"labels":["status:in-testing","owner:acceptance-tester"],"pr":{"number":30,"head":"0badc0de77","comments":[],"checks":"pending","state":"OPEN"}}'
# Gates green from the start: this case checks approvals and CI, not the gates (case 95).
sandbox_gates_green 3
m() { KIT_ROLE="$1" "$BIN/merge.sh" 3 2>&1; }
errors=""

o1="$(m engineer-a)";   case "$o1" in *"only the product-owner merges"*) ;; *) errors="$errors engineer-was-allowed" ;; esac
o2="$(m product-owner)"; case "$o2" in *"MERGE-GATE OK"*) ;; *) errors="$errors PO-without-gate" ;; esac
sandbox_pr_comment 3 'MERGE-GATE OK — HEAD `0badc0de`'
o3="$(m merge-gate)";    case "$o3" in *"PO OK"*) ;; *) errors="$errors gate-without-PO-OK" ;; esac
o4="$(KIT_ROLE=merge-gate "$BIN/status.sh" 3 done x 2>&1)"; case "$o4" in *"last word"*) ;; *) errors="$errors done-without-PO-OK" ;; esac
o5="$(m product-owner)"; case "$o5" in *"CI"*"not green"*) ;; *) errors="$errors pending-CI-let-through" ;; esac
sandbox_issue 3 '{"pr":{"number":30,"head":"0badc0de77","comments":["MERGE-GATE OK — HEAD `0badc0de`","PO OK — HEAD `0badc0de`"],"checks":"pass","state":"OPEN"}}'
o6="$(m merge-gate)";    case "$o6" in *"in-testing → done"*) ;; *) errors="$errors gate-with-PO-OK-rejected:'$(echo "$o6" | tail -1)'" ;; esac

observe "engineer → rejected · PO without MERGE-GATE OK → rejected · merge-gate without PO OK → rejected (merge and done) · CI pending → rejected · merge-gate with PO OK + CI green → $(echo "$o6" | grep -o 'in-testing → done' || echo '?')${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
