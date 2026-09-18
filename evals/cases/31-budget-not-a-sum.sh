#!/usr/bin/env bash
CASE_DESC="the context is the largest turn, not the sum over all turns"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

# sess-sumtrap: three turns of 120000 each. The sum would be 360000 (above the stop),
# the largest turn is 120000 (inconspicuous).
{
  printf '# roster\n\n| Time | Role | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | sess-sumtrap | test-fixture |\n'
} > "$SPRINT/roster.md"

KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
v="$(grep '| engineer-a |' "$SPRINT/budget.md" | awk -F'|' '{gsub(/ /,"",$4); print $4}')"
state_of="$(grep '| engineer-a |' "$SPRINT/budget.md" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')"
flag="$(grep -c '^STOP ' "$SPRINT/budget.md" || true)"

observe "measured $v (the sum would be 360000) · state '$state_of' · stop flags $flag"
echo "OBSERVED: $OBSERVED"
[ "$v" = "120000" ] && [ "$state_of" = "ok" ] && [ "$flag" = "0" ]
