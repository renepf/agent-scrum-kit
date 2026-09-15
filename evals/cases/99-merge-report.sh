#!/usr/bin/env bash
CASE_DESC="merge report: planned records each gate definition; merge.sh prints every AC of the issue once next to its ledger state, the diff's files, and a definition changed since approval — on rejection too, never as a gate"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | grep -v '^  ' | tail -1 | head -c 140)'" ;; esac; }
refuse() { n=$((n + 1)); case "$2" in $3) fail "$1:found-$3" ;; esac; }
# once <name> <output> <id...>: every id starts exactly one report line
once() {
  local name="$1" out="$2" id c; shift 2
  n=$((n + 1))
  for id in "$@"; do
    c="$(printf '%s\n' "$out" | grep -c "^  $id: ")"
    [ "$c" = 1 ] || fail "$name:$id-lines=$c"
  done
}
digests() { python3 - "$BIN" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import gates
doc = gates.parse(open(sys.argv[2]).read())
print(", ".join("%s=%s" % (g["id"], gates.definition_digest(g)) for g in doc["gates"]))
PY
}

L="$SANDBOX/tickets/99/GATES.md"
sandbox_issue 99 '{"body":"AC-1: export writes every row\nAC-2: export button is visible"}'
sandbox_ledger 99 <<'LEDGER'
# Gates: #99 CSV export

OWNS: src/export/**

- [ ] AC-1: export writes every row
  CHECK: python3 tools/check_export.py
  EXPECT: export rows counted
  EVIDENCE: pending

- [ ] AC-2: export button is visible
  EVIDENCE: pending
LEDGER

# a) planned records the definition of every gate as GATES Revision 1 in its approval comment
out="$(KIT_ROLE=product-owner "$BIN/status.sh" 99 planned "scope agreed" 2>&1)"
expect a-planned "$out" '*backlog → planned*'
comment="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["99"]["comments"][-1])' "$SANDBOX/issues.json")"
expect a-gates-line "$comment" "*
GATES Revision 1: \`$(digests "$L")\`*"

sandbox_issue 99 '{"labels":["status:in-testing","owner:acceptance-tester"],"pr":{"number":990,"head":"99999999aa","comments":["MERGE-GATE OK — HEAD `99999999`, eval"],"checks":"pass","state":"OPEN","files":["src/export/csv.py","src/export/button.py"]}}'

# b) a rejected merge prints the report first and writes nothing
s1="$(sandbox_snap 99)"
out="$(KIT_ROLE=product-owner "$BIN/merge.sh" 99 2>&1)"
expect b-rejected "$out" '*Merge abgelehnt*'
expect b-report-before-rejection "$out" '*Merge report #99*PR #990*HEAD 99999999*Merge abgelehnt*'
expect b-AC-1-not-green "$out" '*
  AC-1: not green (*'
expect b-AC-2-not-green "$out" '*
  AC-2: not green (*'
expect b-files "$out" '*files in the diff (2): src/export/csv.py src/export/button.py*'
refuse b-no-change-flag "$out" '*definition changed*'
once b-each-ac-once "$out" AC-1 AC-2
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 99)" ] || fail b:state-changed

# c) a failed read is UNKNOWN in the report, never a state
out="$(KIT_FAKE_READ_FAIL=comments KIT_ROLE=product-owner "$BIN/merge.sh" 99 2>&1)"
expect c-comments-unknown "$out" '*acceptance criteria: UNKNOWN — issue not readable*'
refuse c-comments-no-state "$out" '*  AC-1: *'
out="$(KIT_FAKE_READ_FAIL=body KIT_ROLE=product-owner "$BIN/merge.sh" 99 2>&1)"
expect c-body-unknown "$out" '*acceptance criteria: UNKNOWN — issue not readable*'
out="$(KIT_FAKE_READ_FAIL=pr-files KIT_ROLE=product-owner "$BIN/merge.sh" 99 2>&1)"
expect c-files-unknown "$out" '*files in the diff: UNKNOWN — PR file list not readable*'
refuse c-files-no-count "$out" '*files in the diff (*'
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 99)" ] || fail c:state-changed

# d) CHECK weakened after planned, AC-3 added to the issue without a gate: shown, and the merge still goes through
python3 - "$L" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("CHECK: python3 tools/check_export.py", "CHECK: python3 tools/check_export.py --header-only"))
PY
sandbox_issue 99 '{"body":"AC-1: export writes every row\nAC-2: export button is visible\nAC-3: export names the file by date"}'
sandbox_gates_green 99 nurgates
out="$(KIT_ROLE=product-owner "$BIN/merge.sh" 99 2>&1)"
expect d-merged "$out" '*in-testing → done*'
expect d-AC-1-changed "$out" '*
  AC-1: green for HEAD 99999999; definition changed since approval*'
expect d-AC-2-attested "$out" '*
  AC-2: attested for HEAD 99999999 *'
refuse d-AC-2-unchanged "$(printf '%s\n' "$out" | grep '^  AC-2: ')" '*changed*'
expect d-AC-3-no-gate "$out" '*
  AC-3: no gate in the ledger*'
once d-each-ac-once "$out" AC-1 AC-2 AC-3

# e) a ticket planned without a GATES line: the report says so and flags nothing as changed
sandbox_issue 98 '{"body":"AC-1: das Ergebnis ist beobachtbar","labels":["status:in-testing","owner:acceptance-tester"],"pr":{"number":980,"head":"98989898aa","comments":["MERGE-GATE OK — HEAD `98989898`, eval"],"checks":"pass","state":"OPEN","files":["src/eval.py"]}}'
sandbox_gates_green 98 nurgates
out="$(KIT_ROLE=product-owner "$BIN/merge.sh" 98 2>&1)"
expect e-merged "$out" '*in-testing → done*'
expect e-no-approval "$out" "*approved definitions: none on the issue*"
refuse e-no-change-flag "$out" '*definition changed*'

observe "$((n - failed))/$n checks passed · planned records GATES Revision 1 · report before rejection, each AC once, files listed · failed reads UNKNOWN · changed definition and AC without gate shown, merge not blocked · no GATES line reported${errors:+ · FEHLER:$errors}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$errors" ]
