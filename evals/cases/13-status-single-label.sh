#!/usr/bin/env bash
CASE_DESC="genau ein Status-Label; rfr und rft nehmen den Assignee ab; done schliesst ohne Label"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=engineer-a
fehler=""

for pair in "in-progress:rfr" "in-review:rft"; do
  from="${pair%%:*}"; to="${pair##*:}"; nr=$((RANDOM + 10))
  sandbox_ticket "$nr" "$from"
  "$BIN/tickets.sh" assign "$nr" someone > /dev/null
  "$BIN/status.sh" "$nr" "$to" "eval" > /dev/null 2>&1 || fehler="$fehler $from>$to-abgelehnt"
  n="$("$BIN/tickets.sh" labels "$nr" | grep -c '^status:')"
  a="$("$BIN/tickets.sh" assignees "$nr" | grep -c . || true)"
  [ "$n" = 1 ] || fehler="$fehler $to:$n-Labels"
  [ "$a" = 0 ] || fehler="$fehler $to:Assignee-bleibt"
done

sandbox_ticket 77 in-testing
"$BIN/status.sh" 77 done "gemergt" > /dev/null 2>&1 || fehler="$fehler done-abgelehnt"
n77="$("$BIN/tickets.sh" labels 77 | grep -c '^status:' || true)"
zu="$(python3 -c "import json;print(json.load(open('$SANDBOX/issues.json'))['77'].get('closed', False))")"
[ "$n77" = 0 ] || fehler="$fehler done-traegt-Label"
[ "$zu" = "True" ] || fehler="$fehler done-schliesst-nicht"

observe "rfr und rft: 1 Label, 0 Assignees · done: $n77 Labels, geschlossen=$zu${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
