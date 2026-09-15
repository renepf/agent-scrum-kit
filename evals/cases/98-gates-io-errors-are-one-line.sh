#!/usr/bin/env bash
CASE_DESC="a ledger that cannot be written or is not valid UTF-8 ends in one error line with exit 1, no stack trace, and changes no state"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null

n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
# one_line <name> <output> <rc> <pattern>: exit 1, exactly one line, no Python stack trace, matches pattern
one_line() {
  local bad=""
  [ "$3" = 1 ] || bad="$bad rc=$3"
  [ "$(printf '%s\n' "$2" | grep -c .)" = 1 ] || bad="$bad lines=$(printf '%s\n' "$2" | grep -c .)"
  case "$2" in *Traceback*) bad="$bad stack-trace" ;; esac
  case "$2" in $4) ;; *) bad="$bad '$(printf '%s' "$2" | head -1 | head -c 140)'" ;; esac
  n=$((n + 1)); [ -z "$bad" ] || fail "$1:$bad"
}

# a) unwritable ledger directory: run and attest report it in one line and leave the ledger as it was
L="$SANDBOX/ro/GATES.md"; mkdir -p "$SANDBOX/ro"
printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: result is measured\n  CHECK: python3 -c "print(chr(114)+\\"esult measured\\")"\n  EXPECT: result measured\n  EVIDENCE: pending\n\n- [ ] AC-2: hint is visible\n  EVIDENCE: pending\n' > "$L"
before="$(cat "$L")"
chmod a-w "$SANDBOX/ro"
if [ -w "$SANDBOX/ro" ]; then
  chmod u+w "$SANDBOX/ro"
  echo "BEOBACHTET: BLOCKED — cannot make a directory read-only here (running as root?)"
  exit 3
fi
out="$(python3 "$BIN/gates.py" run "$L" 98989898 "$SANDBOX/ro" engineer-a 30 2>&1)"; rc=$?
one_line a-run-unwritable "$out" "$rc" "*ermission denied*$SANDBOX/ro/*"
out="$(python3 "$BIN/gates.py" attest "$L" AC-2 98989898 acceptance-tester "hint seen" 2>&1)"; rc=$?
one_line a-attest-unwritable "$out" "$rc" "*ermission denied*$SANDBOX/ro/*"
chmod u+w "$SANDBOX/ro"
n=$((n + 1)); [ "$(cat "$L")" = "$before" ] || fail a:ledger-changed

# b) ledger that is not valid UTF-8: every reading command names the file in one line
B="$SANDBOX/bad/GATES.md"; mkdir -p "$SANDBOX/bad"
printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: result \xff\xfe measured\n  CHECK: python3 tools/check.py\n  EXPECT: result measured\n  EVIDENCE: pending\n' > "$B"
for cmd in "planned $B" "lint $B" "unmet $B 98989898 all" "abandoned $B" "qa-lines $B 98989898"; do
  out="$(printf 'AC-1: result measured\n' | python3 "$BIN/gates.py" $cmd 2>&1)"; rc=$?
  one_line "b-${cmd%% *}-invalid-utf8" "$out" "$rc" "*$B*UTF-8*"
done

# c) through status.sh: planned with an invalid ledger is rejected in one reason and writes nothing
sandbox_issue 98 '{"body":"AC-1: result measured"}'
mkdir -p "$SANDBOX/tickets/98" && cp "$B" "$SANDBOX/tickets/98/GATES.md"
s1="$(sandbox_snap 98)"
out="$(KIT_ROLE=product-owner "$BIN/status.sh" 98 planned x 2>&1)"; rc=$?
one_line c-planned-invalid-utf8 "$out" "$rc" "*planned abgelehnt*UTF-8*"
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 98)" ] || fail c:state-changed

observe "$((n - failed))/$n checks passed · unwritable ledger: run, attest, ledger unchanged · invalid UTF-8: planned, lint, unmet, abandoned, qa-lines · status.sh planned rejects and writes nothing${errors:+ · FEHLER:$errors}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$errors" ]
