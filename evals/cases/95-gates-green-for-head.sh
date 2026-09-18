#!/usr/bin/env bash
CASE_DESC="rft only when every executable gate ran green for the current HEAD; a merge only when every manual gate also carries evidence for that HEAD"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
check() { n=$((n + 1)); "${@:2}" || fail "$1"; }

# A project with one commit. The PR of #51 points at its HEAD.
P="$SANDBOX/projekt"
mkdir -p "$P/tools"
cat > "$P/tools/check_export.py" <<'PY'
import pathlib, sys
if pathlib.Path("export.txt").read_text().strip() != "3 rows":
    print("export wrong")
    sys.exit(1)
print("export checked: 3 rows")
PY
echo "3 rows" > "$P/export.txt"
git -C "$P" init -q && git -C "$P" add -A && git -C "$P" commit -qm eins || { echo "OBSERVED: the git commit in the sandbox failed (an identity in ~/.gitconfig?)"; exit 1; }
head1="$(git -C "$P" rev-parse HEAD)"; h1="${head1:0:8}"

pr() { # <head> <labels-json>
  sandbox_issue 51 "{\"labels\":$2,\"pr\":{\"number\":510,\"head\":\"$1\",\"comments\":[],\"checks\":\"pass\",\"state\":\"OPEN\",\"files\":[\"export.txt\"]}}"
  for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS" "MERGE-GATE OK"; do sandbox_pr_comment 51 "$v — HEAD \`${1:0:8}\`, eval
AC-1: mutation row check off → red"; done
}
ledger() { # <check> <expect>
  sandbox_ledger 51 <<LEDGER
# Gates: #51 Export

OWNS: export.txt, tools/**

- [ ] AC-1: the export has 3 rows
  CHECK: $1
  EXPECT: $2
  EVIDENCE: pending

- [ ] AC-2: hint visible on the running build
  EVIDENCE: pending
LEDGER
}
GUT_CHECK="python3 tools/check_export.py"; GUT_EXPECT="export checked: 3 rows"
IN_REVIEW='["status:in-review","owner:qa-ruthless"]'
sandbox_issue 51 '{"body":"AC-1: the export has 3 rows\nAC-2: hint visible on the running build"}'
pr "$head1" "$IN_REVIEW"
ledger "$GUT_CHECK" "$GUT_EXPECT"
rft() { KIT_ROLE=qa-ruthless "$BIN/status.sh" 51 rft x 2>&1; }
run() { (cd "$P" && KIT_ROLE=engineer-a "$BIN/gates.sh" run 51 2>&1); }
L="$SANDBOX/tickets/51/GATES.md"

# a) three PASS, but AC-1 never ran: rft refused
expect a-never-ran "$(rft)" '*rejected*AC-1*'

# b) a run on the HEAD of the PR: AC-1 ticked, the evidence names the HEAD; rft passes
expect b-run "$(run)" '*AC-1*green*'
check b-ticked grep -q '^- \[x\] AC-1:' "$L"
check b-evidence-head grep -q "EVIDENCE: v1 head=$h1 " "$L"
check b-manual-untouched grep -q '^- \[ \] AC-2:' "$L"
expect b-rft "$(rft)" '*in-review → rft*'

# c) a new push: the evidence belongs to the old HEAD, rft refused
echo "notiz" > "$P/NOTIZ.md"; git -C "$P" add -A && git -C "$P" commit -qm zwei
head2="$(git -C "$P" rev-parse HEAD)"; h2="${head2:0:8}"
pr "$head2" "$IN_REVIEW"
expect c-old-HEAD "$(rft)" '*rejected*AC-1*'

# d) the worktree does not stand on the HEAD of the PR: no run, no evidence
git -C "$P" checkout -q "$head1"
before="$(cat "$L")"
expect d-wrong-checkout "$(run)" "*$h1*$h2*"
check d-ledger-unchanged [ "$(cat "$L")" = "$before" ]
git -C "$P" checkout -q -

# e) a run on the new HEAD: rft passes
expect e-run "$(run)" '*AC-1*green*'
expect e-rft "$(rft)" '*in-review → rft*'

# f) the gate definition changed after the run: the evidence no longer fits
pr "$head2" "$IN_REVIEW"
python3 - "$L" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("CHECK: python3 tools/check_export.py", "CHECK: python3 tools/check_export.py --neu"))
PY
expect f-definition-changed "$(rft)" '*rejected*AC-1*'

# g) Failures: exit 0 without EXPECT, EXPECT with exit 1, a timeout. Each unticks and sets pending.
#    The time limit comes from kit.env — an environment variable before the call does not override it.
echo 'KIT_GATE_TIMEOUT="2"' >> "$KIT_ENV_FILE"
for case_spec in "exit0-without-expect|$GUT_CHECK|export checked: 4 rows" \
            "expect-with-exit1|python3 -c \"print('$GUT_EXPECT'); import sys; sys.exit(1)\"|$GUT_EXPECT" \
            "timeout|python3 -c \"import time; time.sleep(5); print('$GUT_EXPECT')\"|$GUT_EXPECT"; do
  name="${case_spec%%|*}"; rest="${case_spec#*|}"; chk="${rest%%|*}"; exp="${rest#*|}"
  ledger "$chk" "$exp"
  # Ticked beforehand with old evidence: a failed run must take both back.
  python3 - "$L" "$h2" <<'PY'
import sys
p, h = sys.argv[1:3]; t = open(p).read()
t = t.replace("- [ ] AC-1:", "- [x] AC-1:", 1).replace("EVIDENCE: pending", "EVIDENCE: v1 head=%s alt" % h, 1)
open(p, "w").write(t)
PY
  og="$(cd "$P" && KIT_ROLE=engineer-a "$BIN/gates.sh" run 51 2>&1)"; rc=$?
  n=$((n + 1)); [ "$rc" != 0 ] || fail "g-$name:exit0"
  check "g-$name-not-unticked" grep -q '^- \[ \] AC-1:' "$L"
  n=$((n + 1)); [ "$(grep -A3 '^- \[ \] AC-1:' "$L" | grep -c 'EVIDENCE: pending')" = 1 ] || fail "g-$name-not-pending"
done
expect g-timeout-reported "$og" '*timed out*'
expect g-rft "$(rft)" '*rejected*AC-1*'

# h) The merge: AC-1 green, AC-2 manual without evidence → refused; evidence only from the acceptance-tester; then the merge
ledger "$GUT_CHECK" "$GUT_EXPECT"
pr "$head2" '["status:in-testing","owner:acceptance-tester"]'
run > /dev/null
merge() { KIT_ROLE=product-owner "$BIN/merge.sh" 51 2>&1; }
expect h-manual-without-evidence "$(merge)" '*rejected*AC-2*'
expect h-attest-role "$(KIT_ROLE=engineer-a "$BIN/gates.sh" attest 51 AC-2 "seen" 2>&1)" '*acceptance-tester*'
expect h-attest-executable "$(KIT_ROLE=acceptance-tester "$BIN/gates.sh" attest 51 AC-1 "seen" 2>&1)" '*AC-1*executable*'
expect h-attest "$(KIT_ROLE=acceptance-tester "$BIN/gates.sh" attest 51 AC-2 "hint visible, screenshot hint.png" 2>&1)" '*AC-2*'
check h-evidence-head grep -q "EVIDENCE: manual head=$h2 by=acceptance-tester" "$L"
expect h-merge "$(merge)" '*in-testing → done*'

observe "$((n - wrong))/$n checks passed · never ran, a run on the HEAD, a new push, a wrong checkout, a changed definition, 3 kinds of failure, a manual gate before the merge, attest only by the acceptance-tester and only for manual gates${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
