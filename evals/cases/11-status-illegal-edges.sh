#!/usr/bin/env bash
CASE_DESC="all 40 forbidden transitions are refused as an edge and leave the state unchanged"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

# Every pair of states that does not stand in protocols/LOOP.md as an edge.
STATES="backlog planned in-progress rfr in-review rft in-testing"
ALLOWED=" backlog>planned planned>in-progress in-progress>rfr rfr>in-review in-review>rft in-review>in-progress rft>in-testing in-testing>in-progress in-testing>done "
# The role is the one responsible for each target — so only the EDGE can explain the refusal.
role_for() {
  case "$1" in
    backlog|planned|done) echo product-owner ;; in-progress|rfr) echo engineer-a ;;
    in-review|rft|in-testing) echo engineer-b ;;
  esac
}

nr=100; refused=0; total=0; passed=""
for from_ in $STATES; do
  for to_ in $STATES done; do
    [ "$from_" = "$to_" ] && continue
    case "$ALLOWED" in *" $from_>$to_ "*) continue ;; esac
    nr=$((nr + 1)); total=$((total + 1))
    sandbox_ticket "$nr" "$from_"
    # engineer-a is the builder, engineer-b reviews: otherwise the four-eyes gate would explain the
    # refusal instead of the missing edge.
    sandbox_issue "$nr" '{"comments":["**In progress** — engineer-a picked it up"]}'
    before="$(sandbox_labels "$nr")"
    # Capture the output first: under pipefail "status.sh | grep" would be wrong as soon as status.sh
    # aborts with exit 1 as intended — even when grep finds the message.
    out="$(KIT_ROLE="$(role_for "$to_")" "$BIN/status.sh" "$nr" "$to_" "eval" 2>&1)"
    after="$(sandbox_labels "$nr")"
    # Two axes: the message AND the unchanged state. Checking only one of them let a
    # switched-off edge lock pass green (mutation probe 2026-09-10).
    if case "$out" in *"forbidden transition"*) true ;; *) false ;; esac && [ "$before" = "$after" ]; then
      refused=$((refused + 1))
    else
      passed="$passed $from_>$to_"
    fi
  done
done
observe "$refused/$total refused as an edge, state unchanged${passed:+ · not correctly refused:$passed}"
echo "OBSERVED: $OBSERVED"
[ "$refused" = "$total" ] && [ "$total" = 40 ]   # 7 source states x 7 targets − 9 allowed edges
