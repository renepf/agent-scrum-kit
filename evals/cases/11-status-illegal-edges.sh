#!/usr/bin/env bash
CASE_DESC="jeder unerlaubte Uebergang wird abgelehnt"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=product-owner

# von:nach — allesamt verboten laut protocols/LOOP.md
BAD="open:in-progress open:rfr open:rft open:closed planned:rfr planned:in-review \
planned:rft planned:closed in-progress:in-review in-progress:rft in-progress:closed \
rfr:rft rfr:closed rfr:in-progress in-review:closed"

nr=100; rejected=0; total=0; leaked=""
for pair in $BAD; do
  from="${pair%%:*}"; to="${pair##*:}"
  nr=$((nr + 1)); total=$((total + 1))
  sandbox_ticket "$nr" "$from"
  if "$BIN/status.sh" "$nr" "$to" "eval" > /dev/null 2>&1; then
    leaked="$leaked $from>$to"
  else
    rejected=$((rejected + 1))
  fi
done
observe "$rejected/$total abgelehnt${leaked:+, durchgelassen:$leaked}"
echo "BEOBACHTET: $OBSERVED"
[ "$rejected" = "$total" ]
