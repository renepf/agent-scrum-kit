#!/usr/bin/env bash
CASE_DESC="omission only visibly: a gate with ABANDON blocks the merge and done with HANDOFF REQUIRED until the product-owner takes the AC out of issue and ledger; review and run skip it"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
pr_state() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["pr"].get("state","OPEN"))' "$SANDBOX/issues.json" "$1"; }

ledger() { # <nr> <with-abandon: yes|no>
  {
    printf '# Gates: #%s print view\n\nOWNS: src/print/**\n\n' "$1"
    printf -- '- [ ] AC-1: the print view shows every row\n  CHECK: python3 tools/check_print.py\n  EXPECT: print view checked\n  EVIDENCE: pending\n\n'
    if [ "$2" = yes ]; then
      printf -- '- [ ] AC-2: the print lands on the printer\n  CHECK: python3 tools/check_printer.py\n  EXPECT: printer checked\n  EVIDENCE: pending\n\n'
      printf 'ABANDON: AC-2 printer API missing in the test system, follow-up ticket #99 created\n'
    fi
  } | sandbox_ledger "$1"
}

# a) The merge and done with an open ABANDON: refused, nothing merged, nothing written
sandbox_issue 81 '{"body":"AC-1: the print view shows every row\nAC-2: the print lands on the printer","labels":["status:in-testing","owner:acceptance-tester"],"pr":{"number":810,"head":"81818181aa","comments":["MERGE-GATE OK — HEAD `81818181`, eval","PO OK — HEAD `81818181`, eval"],"checks":"pass","state":"OPEN","files":["src/print/view.py"]}}'
ledger 81 yes
sandbox_gates_green 81 gatesonly
s1="$(sandbox_snap 81)"
expect a-merge-po "$(KIT_ROLE=product-owner "$BIN/merge.sh" 81 2>&1)" '*HANDOFF REQUIRED*AC-2*printer API missing*'
expect a-merge-gate "$(KIT_ROLE=merge-gate "$BIN/merge.sh" 81 2>&1)" '*HANDOFF REQUIRED*AC-2*'
expect a-done-direkt "$(KIT_ROLE=product-owner "$BIN/status.sh" 81 done x 2>&1)" '*HANDOFF REQUIRED*AC-2*'
n=$((n + 1)); [ "$(pr_state 81)" = OPEN ] || fail "a:PR-gemergt-trotz-ABANDON($(pr_state 81))"
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 81)" ] || fail a:state-changed

# b) The review does not block it: rft without evidence and without a QA line for the abandoned gate
sandbox_issue 82 '{"body":"AC-1: the print view shows every row\nAC-2: the print lands on the printer","labels":["status:in-review","owner:qa-ruthless"],"pr":{"number":820,"head":"82828282aa","comments":["SIMPLICITY PASS — HEAD `82828282`, eval","SECURITY PASS — HEAD `82828282`, eval","QA PASS — HEAD `82828282`, eval\nAC-1: mutation Zeilenzaehler aus → red"],"files":["src/print/view.py"]}}'
ledger 82 yes
sandbox_gates_green 82 gatesonly
python3 - "$SANDBOX/tickets/82/GATES.md" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
head, sep, rest = t.partition("- [x] AC-2:")
rest = re.sub(r"EVIDENCE: .*", "EVIDENCE: pending", rest, count=1)
open(p, "w").write(head + "- [ ] AC-2:" + rest)
PY
expect b-rft-skips "$(KIT_ROLE=qa-ruthless "$BIN/status.sh" 82 rft x 2>&1)" '*in-review → rft*'

# c) The run skips an abandoned gate, even when its CHECK would fail
P="$SANDBOX/lauf"; mkdir -p "$P"
printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: rows counted\n  CHECK: python3 -c "print(chr(114)+\\"ows counted\\")"\n  EXPECT: rows counted\n  EVIDENCE: pending\n\n- [ ] AC-2: printer reached\n  CHECK: python3 -c "import sys; sys.exit(3)"\n  EXPECT: printer reached\n  EVIDENCE: pending\n\nABANDON: AC-2 no printer in the test system\n' > "$P/GATES.md"
oc="$(python3 "$BIN/gates.py" run "$P/GATES.md" 83838383 "$P" engineer-a 30 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "c:rc=$rc:'$(echo "$oc" | tr '\n' ' ' | head -c 120)'"
case "$oc" in *AC-2*) fail "c:AC-2-ran" ;; esac
expect c-AC-1-green "$oc" '*AC-1 green*'

# d) The product-owner has the last word: AC-2 taken out of issue and ledger by a follow-up ticket → the merge passes
sandbox_issue 81 '{"body":"AC-1: the print view shows every row\n\nthe print on the printer: follow-up ticket #99"}'
ledger 81 no
sandbox_gates_green 81 gatesonly
expect d-merge-after-the-decision "$(KIT_ROLE=product-owner "$BIN/merge.sh" 81 2>&1)" '*in-testing → done*'

observe "$((n - wrong))/$n checks passed · the merge (PO, merge-gate) and done refused with ABANDON, the PR open, nothing written · rft skips · the run skips · merged after the PO decision${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
