#!/usr/bin/env bash
CASE_DESC="the working contract carries the anti-invention rules and stays lean"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

C="$KIT_ROOT/AGENTS.md"
errors=""
grep -q 'UNKNOWN — <where to clear it>' "$C" || errors="$errors UNKNOWN-rule"
grep -q 'A failed tool call is a' "$C" || errors="$errors failure-rule"
grep -q 'intermediate state is not a result' "$C" || errors="$errors intermediate-state-rule"
grep -q 'syntax check is not a run' "$C" || errors="$errors syntax-check-rule"
grep -q 'never spawns a subagent' "$C" || errors="$errors subagent-rule"
for rp in 'F1' 'D1' 'R1' 'Q1' 'A1'; do
  grep -q "\`$rp\`" "$C" || errors="$errors reference-point-$rp"
done
# Past 300 lines the result measurably worsens.
lines="$(wc -l < "$C" | tr -d ' ')"
[ "$lines" -le 300 ] || errors="$errors too-long($lines)"

# One source, several names: CLAUDE.md and .cursorrules must not duplicate.
grep -q 'AGENTS.md' "$KIT_ROOT/CLAUDE.md" || errors="$errors CLAUDE.md-does-not-point-at-AGENTS.md"
grep -q 'AGENTS.md' "$KIT_ROOT/.cursorrules" || errors="$errors cursorrules-does-not-point-at-AGENTS.md"
[ "$(wc -l < "$KIT_ROOT/CLAUDE.md" | tr -d ' ')" -le 10 ] || errors="$errors CLAUDE.md-duplicates"

observe "AGENTS.md $lines lines, every rule and reference point present, CLAUDE.md and .cursorrules point at it${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
