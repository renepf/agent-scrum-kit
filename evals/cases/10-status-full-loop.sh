#!/usr/bin/env bash
CASE_DESC="die volle Vorwaertsschleife laeuft von backlog bis done, jede Kante mit ihrer Rolle"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 1 '{"pr":{"number":10,"head":"a1b2c3d4e5f6","comments":[],"checks":"pass","state":"OPEN"}}'

weg=""; fehler=""
st() { if KIT_ROLE="$1" "$BIN/status.sh" 1 "$2" "eval" > /dev/null 2>&1; then weg="$weg>$2"; else fehler="$fehler $1:$2"; fi; }
st product-owner planned
st engineer-a in-progress
st engineer-a rfr
st qa-ruthless in-review
KIT_ROLE=simplicity-reviewer "$BIN/claim.sh" 1 > /dev/null 2>&1 || fehler="$fehler claim-simplicity"
KIT_ROLE=security-engineer "$BIN/claim.sh" 1 > /dev/null 2>&1 || fehler="$fehler claim-security"
for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 1 "$v — HEAD \`a1b2c3d4\`, eval"; done
st security-engineer rft
st acceptance-tester in-testing
sandbox_pr_comment 1 "MERGE-GATE OK — HEAD \`a1b2c3d4\`, eval"
KIT_ROLE=product-owner "$BIN/merge.sh" 1 > /dev/null 2>&1 && weg="$weg>done(merge.sh)" || fehler="$fehler merge.sh"

zustand="$(python3 -c 'import json,sys; i=json.load(open(sys.argv[1]))["1"]; print(i["state"], i["pr"]["state"], ",".join(i["labels"]) or "keine-Labels")' "$SANDBOX/issues.json")"
[ "$zustand" = "closed MERGED keine-Labels" ] || fehler="$fehler endzustand='$zustand'"

observe "Weg: backlog$weg · Ende: $zustand${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
