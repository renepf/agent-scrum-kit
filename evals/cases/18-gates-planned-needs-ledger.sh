#!/usr/bin/env bash
CASE_DESC="planned demands a ledger that covers every AC-<n> of the issue in every spelling with a gate and starts fresh; a rejection writes nothing"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 120)'" ;; esac; }
plan() { KIT_ROLE=product-owner "$BIN/status.sh" "$1" planned "Verdict: ok" 2>&1; }
# Rejected with a message, and neither the issue nor tickets/<nr>/ have changed.
rejected() {
  local s1 s2 out
  s1="$(sandbox_snap "$2")"; out="$(plan "$2")"; s2="$(sandbox_snap "$2")"
  expect "$1" "$out" "$3"
  [ "$s1" = "$s2" ] || fail "$1:state-changed"
}
head_of() { printf '# Gates: #31 Export\n\nOWNS: src/export/**\n\n'; }
gate() { printf -- '- [ ] %s: %s\n  CHECK: python3 tools/check_export.py %s\n  EXPECT: export checked %s\n  EVIDENCE: pending\n\n' "$1" "$2" "$1" "$1"; }

sandbox_issue 31 '{"body":"As a user I want to export my list.\n\n1. AC-1: the export creates a file\n2. AC-2: an empty list gives an empty file\n3. AC-3: a write error appears as a message"}'

# The coverage check reports it — not the lint, which also rejects a missing ledger.
rejected a-no-ledger 31 '*planned rejected — no ledger*'
{ head_of; gate AC-1 file; gate AC-2 empty; } | sandbox_ledger 31
rejected b-AC-without-gate 31 '*without a gate*AC-3*'
{ head_of; gate AC-1 file; gate AC-2 empty; gate AC-3 message; gate AC-9 does-not-exist; } | sandbox_ledger 31
rejected c-unknown-AC 31 '*AC-9*'
{ head_of; printf -- '- [ ] AC-1: file\n  CHECK: python3 tools/check_export.py\n  EVIDENCE: pending\n\n'; gate AC-2 empty; gate AC-3 message; } | sandbox_ledger 31
rejected d-CHECK-without-EXPECT 31 '*AC-1*CHECK and EXPECT*'
{ head_of; printf -- '- [x] AC-1: file\n  CHECK: python3 tools/check_export.py AC-1\n  EXPECT: export checked AC-1\n  EVIDENCE: pending\n\n'; gate AC-2 empty; gate AC-3 message; } | sandbox_ledger 31
rejected e-already-ticked 31 '*ticked*AC-1*'
{ head_of; gate AC-1 file; gate AC-2 empty; gate AC-3 message; printf 'ABANDON: AC-3 too expensive\n'; } | sandbox_ledger 31
rejected f-ABANDON-upfront 31 '*ABANDON*AC-3*'
sandbox_issue 32 '{"body":"Something should get better."}'
{ printf '# Gates: #32\n\nOWNS: src/**\n\n'; gate AC-1 something; } | sandbox_ledger 32
rejected g-issue-without-AC 32 '*names no AC*'

# h) AC spellings: every one counts; inside a code fence or an HTML comment none does.
#    The ledger covers only AC-1 — so every issue with a further AC must be rejected.
printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: a\n  CHECK: python3 tools/check_a.py\n  EXPECT: a measured\n  EVIDENCE: pending\n' > "$SANDBOX/nur-ac1.md"
while IFS=';' read -r name text want; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  printf '%b' "$text" | python3 "$BIN/gates.py" planned "$SANDBOX/nur-ac1.md" > /dev/null 2>&1 && got=through || got=rejected
  [ "$got" = "$want" ] || fail "h-$name:$got"
done <<'TABLE'
line;AC-1: a\nAC-2: b;rejected
checkbox;AC-1: a\n- [ ] AC-2: b;rejected
heading;AC-1: a\n### AC-2: b;rejected
quote;AC-1: a\n> AC-2: b;rejected
table;AC-1: a\n| AC-2 | b |;rejected
bold;AC-1: a\n**AC-2** — b;rejected
crlf;AC-1: a\r\nAC-2: b\r\n;rejected
only-ac1;1. AC-1: a;through
code-fence;AC-1: a\n```\nAC-2: b\n```;through
html-comment;<!--\nAC-2: <result>\n-->\nAC-1: a;through
TABLE

# i) counter-check: a complete, fresh ledger
{ head_of; gate AC-1 file; gate AC-2 empty; gate AC-3 message; } | sandbox_ledger 31
oi="$(plan 31)"
expect i-complete "$oi" '*backlog → planned*'

observe "$((n - wrong))/$n checks passed · 7 rejections with a byte comparison of the issue and tickets/<nr>/ · 10 AC spellings · counter-check: $(echo "$oi" | tail -1)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
