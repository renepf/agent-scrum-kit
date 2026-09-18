#!/usr/bin/env bash
CASE_DESC="job descriptions contain no host vocabulary"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# The word list is deliberately narrow: product names of hosts, not general terms.
hits=""
for w in claude Claude codex Codex cursor Cursor "Hermes" "PI Code" "/clear" "/compact" "Subagent-Tool" "Task-Tool"; do
  hits="$(grep -rl -- "$w" "$KIT_ROOT"/roles/*.md 2>/dev/null | tr '\n' ' ')"
  [ -n "$hits" ] && hits="$hits '$w' in $hits;"
done

observe "${hits:-no host vocabulary in roles/}"
echo "OBSERVED: $OBSERVED"
[ -z "$hits" ]
