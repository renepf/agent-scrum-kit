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
st qa-ruthless in-review
KIT_ROLE=simplicity-reviewer "$BIN/claim.sh" 1 > /dev/null 2>&1 || errors="$errors claim-simplicity"
KIT_ROLE=security-engineer "$BIN/claim.sh" 1 > /dev/null 2>&1 || errors="$errors claim-security"
for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 1 "$v — HEAD \`a1b2c3d4\`, eval"; done
sandbox_gates_green 1
st security-engineer rft
st acceptance-tester in-testing
sandbox_pr_comment 1 "MERGE-GATE OK — HEAD \`a1b2c3d4\`, eval"
KIT_ROLE=product-owner "$BIN/merge.sh" 1 > /dev/null 2>&1 && path="$path>done(merge.sh)" || errors="$errors merge.sh"

state="$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["1"]; print(i["state"], i["pr"]["state"], ",".join(i["labels"]) or "no-labels")' "$SANDBOX/issues.json")"
[ "$state" = "closed MERGED no-labels" ] || errors="$errors end_state='$state'"

observe "path: backlog$path · end: $state${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
