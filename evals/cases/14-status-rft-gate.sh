#!/usr/bin/env bash
CASE_DESC="rft demands QA, SIMPLICITY and SECURITY PASS for the CURRENT HEAD; a push invalidates old verdicts"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 5 '{"labels":["status:in-review","owner:engineer-b"],"pr":{"number":50,"head":"11111111aaaa","comments":[]}}'
# engineer-a built it, engineer-b reviews it — every verdict therefore names engineer-b.
sandbox_issue 5 '{"comments":["**In progress** — engineer-a picked it up"]}'
try() { KIT_ROLE=engineer-b "$BIN/status.sh" 5 rft x 2>&1; }

errors=""
sandbox_pr_comment 5 'QA PASS — HEAD `11111111` · engineer-b'
sandbox_pr_comment 5 'SIMPLICITY PASS — HEAD `11111111` · engineer-b'
o1="$(try)"; case "$o1" in *"missing"*"SECURITY PASS"*) ;; *) errors="$errors missing-verdict-not-detected" ;; esac

sandbox_pr_comment 5 'SECURITY PASS — HEAD `11111111` · engineer-b'
sandbox_issue 5 '{"pr":{"number":50,"head":"22222222bbbb","comments":["QA PASS — HEAD `11111111` · engineer-b","SIMPLICITY PASS — HEAD `11111111` · engineer-b","SECURITY PASS — HEAD `11111111` · engineer-b"]}}'
o2="$(try)"; case "$o2" in *"missing for HEAD 22222222"*) ;; *) errors="$errors old-HEAD-let-through" ;; esac

sandbox_pr_comment 5 'By the way: a QA PASS would be nice — HEAD `22222222` · engineer-b'
o3="$(try)"; case "$o3" in *"missing"*"QA PASS"*) ;; *) errors="$errors verdict-not-in-first-line-accepted" ;; esac

for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 5 "$v — HEAD \`22222222\` · engineer-b, checked"; done
sandbox_gates_green 5 "" engineer-b
o4="$(try)"; case "$o4" in *"in-review → rft"*) ;; *) errors="$errors valid-verdicts-rejected:'$o4'" ;; esac

observe "2 of 3 → rejected · all 3 for the old HEAD → rejected · verdict mid-sentence → rejected · all 3 for the new HEAD → $(echo "$o4" | tail -1)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
