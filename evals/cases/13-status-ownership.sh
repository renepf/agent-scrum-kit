#!/usr/bin/env bash
CASE_DESC="exactly one status label; ownership through owner:<role>; rfr and rft are ownerless"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 7 '{"assignees":["one-account"],"pr":{"number":70,"head":"77777777aa","comments":["QA PASS — HEAD `77777777` · engineer-b","SIMPLICITY PASS — HEAD `77777777` · engineer-b","SECURITY PASS — HEAD `77777777` · engineer-b"]}}'
sandbox_plannable 7

errors=""
KIT_ROLE=product-owner "$BIN/status.sh" 7 planned x > /dev/null 2>&1
KIT_ROLE=engineer-a "$BIN/status.sh" 7 in-progress x > /dev/null 2>&1
a="$(sandbox_labels 7)"
KIT_ROLE=engineer-b "$BIN/status.sh" 7 rfr x > /dev/null 2>&1 && errors="$errors foreign-engineer-was-allowed-to-hand-off"
KIT_ROLE=engineer-a "$BIN/status.sh" 7 rfr x > /dev/null 2>&1
b="$(sandbox_labels 7)"
ass="$(KIT_ROLE=product-owner "$BIN/tickets.sh" assignees 7 | grep -c . || true)"
# engineer-a built it, so engineer-b reviews it. There is no second reviewer that could claim the
# ticket on top (bin/claim.sh is gone) — in-review carries exactly one owner, the reviewer.
KIT_ROLE=engineer-b "$BIN/status.sh" 7 in-review x > /dev/null 2>&1
c="$(sandbox_labels 7)"
sandbox_gates_green 7 "" engineer-b
KIT_ROLE=engineer-b "$BIN/status.sh" 7 rft x > /dev/null 2>&1
d="$(sandbox_labels 7)"

[ "$a" = "owner:engineer-a status:in-progress" ] || errors="$errors in-progress='$a'"
[ "$b" = "status:rfr" ] || errors="$errors rfr='$b'"
[ "$ass" = 0 ] || errors="$errors assignee-stays($ass)"
[ "$c" = "owner:engineer-b status:in-review" ] || errors="$errors in-review='$c'"
[ "$d" = "status:rft" ] || errors="$errors rft-not-ownerless='$d'"
n_status="$(printf '%s\n%s\n%s\n%s\n' "$a" "$b" "$c" "$d" | tr ' ' '\n' | grep -c '^status:' || true)"

observe "in-progress: $a · rfr: $b (assignees $ass) · in-review: $c · rft: $d${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ] && [ "$n_status" = 4 ]
