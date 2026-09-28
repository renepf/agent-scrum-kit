#!/usr/bin/env bash
CASE_DESC="the full forward loop runs from backlog to done, every edge with its role"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 1 '{"pr":{"number":10,"head":"a1b2c3d4e5f6","comments":[],"checks":"pass","state":"OPEN"}}'
sandbox_plannable 1

path=""; errors=""
st() { if KIT_ROLE="$1" "$BIN/status.sh" 1 "$2" "eval" > /dev/null 2>&1; then path="$path>$2"; else errors="$errors $1:$2"; fi; }
st product-owner planned
st engineer-a in-progress
st engineer-a rfr
# engineer-a built it, so engineer-b reviews it — and wears every hat from here to the acceptance.
st engineer-b in-review
# There is no second reviewer to claim the ticket any more (bin/claim.sh is gone): the one
# reviewing engineer takes ownership at in-review, which is what the claim used to show.
case "$(sandbox_labels 1)" in *"owner:engineer-b"*) ;; *) errors="$errors review-owner='$(sandbox_labels 1)'" ;; esac
for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 1 "$v — HEAD \`a1b2c3d4\` · engineer-b, eval"; done
sandbox_gates_green 1 "" engineer-b
st engineer-b rft
st engineer-b in-testing
sandbox_pr_comment 1 "MERGE-GATE OK — HEAD \`a1b2c3d4\` · engineer-b, eval"
KIT_ROLE=product-owner "$BIN/merge.sh" 1 > /dev/null 2>&1 && path="$path>done(merge.sh)" || errors="$errors merge.sh"

state="$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["1"]; print(i["state"], i["pr"]["state"], ",".join(i["labels"]) or "no-labels")' "$SANDBOX/issues.json")"
[ "$state" = "closed MERGED no-labels" ] || errors="$errors end_state='$state'"

observe "path: backlog$path · end: $state${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
