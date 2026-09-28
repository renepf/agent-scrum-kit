#!/usr/bin/env bash
# Merge a ticket and set it to done — only when every condition holds for the CURRENT PR HEAD.
#
#   bin/merge.sh 795
#
# Only the product-owner merges (owner 2026-09-28; the merge-gate role is gone). It needs
# 'MERGE-GATE OK — HEAD `<sha8>` · <engineer>' in the PR — written by the REVIEWING engineer, never
# by the builder — and green CI.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ $# -ge 1 ] || die "usage: bin/merge.sh <ticket>"
TICKET="$1"; R="$(role)"
case "$R" in product-owner) ;; *) die "only the product-owner merges — not $R" ;; esac
"$BIN_DIR/preflight.sh" > /dev/null || die "preflight failed — stop and report"

NEED=("MERGE-GATE OK")
verdicts_missing "$TICKET" "${NEED[@]}"
# Merge report: a measurement for the product-owner, never a gate. It prints before any rejection;
# a failed read is UNKNOWN in the report and stops nothing.
echo "Merge report #$TICKET · PR #$VERDICT_PR · HEAD $VERDICT_HEAD8"
if R_COMMENTS="$("$BIN_DIR/tickets.sh" comments "$TICKET" 2>&1)" && R_BODY="$("$BIN_DIR/tickets.sh" body "$TICKET" 2>&1)"; then
  { printf '%s\0' "$R_COMMENTS"; printf '%s\n' "$R_BODY"; } \
    | python3 "$BIN_DIR/gates.py" report "$TICKETS_DIR/$TICKET/GATES.md" "$VERDICT_HEAD8" 2>&1 || true
else
  echo "  acceptance criteria: UNKNOWN — issue not readable: ${R_BODY:-$R_COMMENTS}"
fi
if R_FILES="$("$BIN_DIR/tickets.sh" pr-files "$VERDICT_PR" 2>&1)"; then
  echo "  files in the diff ($(printf '%s\n' "$R_FILES" | grep -c .)): $(printf '%s\n' "$R_FILES" | grep . | tr '\n' ' ')"
else
  echo "  files in the diff: UNKNOWN — PR file list not readable: $R_FILES"
fi
[ -z "$VERDICT_MISSING" ] || die "#$TICKET: merge rejected — in PR #$VERDICT_PR the following is missing for HEAD $VERDICT_HEAD8:$VERDICT_MISSING"
# An abandoned AC never falls away silently: while an ABANDON stands, no merge.
HANDOFF="$(python3 "$BIN_DIR/gates.py" abandoned "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" || die "#$TICKET: merge rejected — $HANDOFF"
# Every gate for this HEAD: executable ones ran green, manual ones attested.
GATE_MSG="$(python3 "$BIN_DIR/gates.py" unmet "$TICKETS_DIR/$TICKET/GATES.md" "$VERDICT_HEAD8" all 2>&1)" \
  || die "#$TICKET: merge rejected — $GATE_MSG"

# Measure CI fresh. Only exit 0 means green; running or red is not a result.
set +e; CHECKS="$("$BIN_DIR/tickets.sh" pr-checks "$VERDICT_PR" 2>&1)"; RC=$?; set -e
[ "$RC" -eq 0 ] || die "#$TICKET: merge rejected — CI of PR #$VERDICT_PR not green (exit $RC): $CHECKS"

"$BIN_DIR/tickets.sh" pr-merge "$VERDICT_PR"
STATE="$("$BIN_DIR/tickets.sh" pr-state "$VERDICT_PR")"
case "$STATE" in MERGED*) ;; *) die "PR #$VERDICT_PR is not MERGED after the merge but '$STATE' — do not set done" ;; esac

"$BIN_DIR/status.sh" "$TICKET" done "PR #$VERDICT_PR merged as ${STATE#MERGED } (HEAD $VERDICT_HEAD8) by $R"
echo "Check the branch cleanup separately — a merge call with exit 0 says nothing about the deleted branch."
