#!/usr/bin/env bash
CASE_DESC="the gate lint against blind witnesses: planned and rft refuse oracles that cannot fall; rft demands one QA line 'mutation → red' per executable gate"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
# The builder of a ticket comes from the comment history (ticket_builder in bin/common.sh).
BUILT_BY_A='{"comments":["**In progress** — engineer-a picked it up"]}'
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }

# a) The rules one at a time: kind | title | CHECK | EXPECT | issue text (empty = "AC-1: <title>") | expectation
while IFS='|' read -r kind title chk exp body want; do
  [ -n "$kind" ] || continue
  n=$((n + 1))
  {
    printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: %s\n' "$title"
    [ "$kind" = manual ] || printf '  CHECK: %s\n  EXPECT: %s\n' "$chk" "$exp"
    printf '  EVIDENCE: pending\n'
  } > "$SANDBOX/lint.md"
  out="$(printf '%b\n' "${body:-AC-1: $title}" | python3 "$BIN/gates.py" lint "$SANDBOX/lint.md" 2>&1)"; rc=$?
  case "$want" in
    ok) [ "$rc" = 0 ] && [ -z "$out" ] || fail "a:'$chk'/'$exp'/'$title':rc=$rc:'$(echo "$out" | head -1)'" ;;
    error:*) [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "^ERROR AC-1 \[${want#error:}\]" || fail "a:'$chk'/'$exp':want=$want:rc=$rc:'$(echo "$out" | head -1)'" ;;
    hint:*) [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "^HINT AC-1 \[${want#hint:}\]" || fail "a:'$title':want=$want:rc=$rc:'$(echo "$out" | head -1)'" ;;
    *) fail "a:table-row-without-an-expectation:'$kind|$title|$chk|$exp|$body'" ;;
  esac
done <<'TABELLE'
runnable|the export has 3 rows|echo ok|export checked||error:tautological-check
runnable|the export has 3 rows|printf 'export checked'|export checked||error:tautological-check
runnable|the export has 3 rows|true|export checked||error:tautological-check
runnable|the export has 3 rows|python3 tools/check.py|ok||error:weak-expect
runnable|the export has 3 rows|python3 tools/check.py|Bestanden||error:weak-expect
runnable|the export has 3 rows|python3 tools/check.py && echo fertig|fertig||error:weak-expect
runnable|the export has 3 rows|python3 tools/check.py|/usr/bin/app/||error:path-read-as-regex
runnable|the export has 3 rows|python3 tools/count.py|3|AC-1: the export has 3 rows|error:copied-number
runnable|the export has 3 rows|python3 tools/count.py|export counts 3 rows||ok
runnable|the export has 3 rows|python3 tools/check.py|/export checked: \d+ rows/||ok
manual|the hint is visible||||hint:manual-gate
manual|the list shows 3 entries||||hint:unmeasured-number
runnable|Paywall verbessern|python3 tools/check.py|paywall checked||hint:activity-not-outcome
runnable|improve the paywall|python3 tools/check.py|paywall checked||hint:activity-not-outcome
TABELLE

# b) planned refuses a blind oracle and writes nothing
sandbox_issue 61 '{"body":"AC-1: the export has 3 rows"}'
printf '# Gates: #61\n\nOWNS: src/**\n\n- [ ] AC-1: the export has 3 rows\n  CHECK: echo export checked\n  EXPECT: export checked\n  EVIDENCE: pending\n' | sandbox_ledger 61
s1="$(sandbox_snap 61)"
expect b-planned-blind "$(KIT_ROLE=product-owner "$BIN/status.sh" 61 planned x 2>&1)" '*rejected*tautological-check*'
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 61)" ] || fail b:state-changed

# c) Hints do not refuse and stand in the planned comment
sandbox_issue 62 '{"body":"AC-1: the export has 3 rows\nAC-2: the hint is visible"}'
printf '# Gates: #62\n\nOWNS: src/**\n\n- [ ] AC-1: the export has 3 rows\n  CHECK: python3 tools/check_export.py\n  EXPECT: export checked: 3 rows\n  EVIDENCE: pending\n\n- [ ] AC-2: the hint is visible\n  EVIDENCE: pending\n' | sandbox_ledger 62
expect c-planned-with-a-hint "$(KIT_ROLE=product-owner "$BIN/status.sh" 62 planned x 2>&1)" '*backlog → planned*'
k62="$(KIT_ROLE=product-owner "$BIN/tickets.sh" comments 62)"
expect c-hint-in-the-comment "$k62" '*Lint hints*AC-2*manual-gate*'

# d) rft: the CHECK weakened to a fixed echo after planned and run green because of it → refused
# engineer-a built the ticket (the comment status.sh writes itself), engineer-b reviews it: the
# builder is turned away at rft, and every verdict names its reviewer.
sandbox_issue 63 '{"labels":["status:in-review","owner:engineer-b"],"pr":{"number":630,"head":"63636363aa","comments":[],"files":["src/a.py"]}}'
sandbox_issue 63 "$BUILT_BY_A"
sandbox_plannable 63
for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 63 "$v — HEAD \`63636363\` · engineer-b, eval"; done
python3 - "$SANDBOX/tickets/63/GATES.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("CHECK: python3 tools/check_result.py", "CHECK: echo result checked"))
PY
sandbox_gates_green 63
expect d-rft-weakened "$(KIT_ROLE=engineer-b "$BIN/status.sh" 63 rft x 2>&1)" '*rejected*tautological-check*'

# e) rft: one QA line "AC-<n>: mutation … → red" per executable gate for the current HEAD; manual ones need none
sandbox_issue 64 '{"body":"AC-1: the export has 3 rows\nAC-2: an empty list gives an empty file\nAC-3: the hint is visible","labels":["status:in-review","owner:engineer-b"],"pr":{"number":640,"head":"64646464aa","comments":[],"files":["src/a.py"]}}'
sandbox_issue 64 "$BUILT_BY_A"
printf '# Gates: #64\n\nOWNS: src/**\n\n- [ ] AC-1: the export has 3 rows\n  CHECK: python3 tools/check_export.py\n  EXPECT: export checked: 3 rows\n  EVIDENCE: pending\n\n- [ ] AC-2: an empty list gives an empty file\n  CHECK: python3 tools/check_empty.py\n  EXPECT: empty file checked\n  EVIDENCE: pending\n\n- [ ] AC-3: the hint is visible\n  EVIDENCE: pending\n' | sandbox_ledger 64
sandbox_gates_green 64 gatesonly
for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 64 "$v — HEAD \`64646464\` · engineer-b, eval"; done
rft64() { KIT_ROLE=engineer-b "$BIN/status.sh" 64 rft x 2>&1; }
sandbox_pr_comment 64 'QA PASS — HEAD `64646464` · engineer-b, 2 tests added'
expect e-without-lines "$(rft64)" '*rejected*mutation*AC-1*AC-2*'
sandbox_pr_comment 64 'QA PASS — HEAD `11111111` · engineer-b, old
AC-1: mutation Zeilenzaehler aus → red
AC-2: mutation Leerpruefung aus → red'
expect e-old-HEAD-does-not-count "$(rft64)" '*rejected*mutation*AC-1*AC-2*'
sandbox_pr_comment 64 'QA PASS — HEAD `64646464` · engineer-b, addendum
AC-1: mutation Zeilenzaehler aus → red'
oe="$(rft64)"
expect e-only-AC-1 "$oe" '*rejected*mutation*AC-2*'
case "$oe" in *AC-3*) fail e:manual-gate-demanded ;; esac
sandbox_pr_comment 64 'QA PASS — HEAD `64646464` · engineer-b, addendum
AC-2: mutation Leerpruefung aus → red'
expect e-both "$(rft64)" '*in-review → rft*'

observe "$((n - wrong))/$n checks passed · 14 lint rule cases · planned refused a blind oracle without write access · hints in the comment · rft refused after the weakening · QA lines: none, an old HEAD, incomplete, complete${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
