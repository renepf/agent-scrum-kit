#!/usr/bin/env bash
CASE_DESC="genau ein Status-Label; Besitz ueber owner:<rolle>; rfr und rft sind besitzerlos"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 7 '{"assignees":["ein-account"],"pr":{"number":70,"head":"77777777aa","comments":["QA PASS — HEAD `77777777`","SIMPLICITY PASS — HEAD `77777777`","SECURITY PASS — HEAD `77777777`"]}}'
sandbox_plannable 7

fehler=""
KIT_ROLE=product-owner "$BIN/status.sh" 7 planned x > /dev/null 2>&1
KIT_ROLE=engineer-a "$BIN/status.sh" 7 in-progress x > /dev/null 2>&1
a="$(sandbox_labels 7)"
KIT_ROLE=engineer-b "$BIN/status.sh" 7 rfr x > /dev/null 2>&1 && fehler="$fehler fremder-Engineer-durfte-abgeben"
KIT_ROLE=engineer-a "$BIN/status.sh" 7 rfr x > /dev/null 2>&1
b="$(sandbox_labels 7)"
ass="$(KIT_ROLE=product-owner "$BIN/tickets.sh" assignees 7 | grep -c . || true)"
KIT_ROLE=qa-ruthless "$BIN/status.sh" 7 in-review x > /dev/null 2>&1
KIT_ROLE=security-engineer "$BIN/claim.sh" 7 > /dev/null 2>&1
c="$(sandbox_labels 7)"
sandbox_gates_green 7
KIT_ROLE=security-engineer "$BIN/status.sh" 7 rft x > /dev/null 2>&1
d="$(sandbox_labels 7)"

[ "$a" = "owner:engineer-a status:in-progress" ] || fehler="$fehler in-progress='$a'"
[ "$b" = "status:rfr" ] || fehler="$fehler rfr='$b'"
[ "$ass" = 0 ] || fehler="$fehler assignee-bleibt($ass)"
[ "$c" = "owner:qa-ruthless owner:security-engineer status:in-review" ] || fehler="$fehler in-review='$c'"
[ "$d" = "status:rft" ] || fehler="$fehler rft-nicht-besitzerlos='$d'"
n_status="$(printf '%s\n%s\n%s\n%s\n' "$a" "$b" "$c" "$d" | tr ' ' '\n' | grep -c '^status:' || true)"

observe "in-progress: $a · rfr: $b (Assignees $ass) · in-review nach claim: $c · rft: $d${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ] && [ "$n_status" = 4 ]
