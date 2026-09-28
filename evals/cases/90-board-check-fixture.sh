#!/usr/bin/env bash
CASE_DESC="board-check detects missing, surplus and wrongly ordered options and missing labels; writes board.env only on success"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
cat >> "$KIT_ENV_FILE" <<'ENV'
KIT_BOARD="github-project"
KIT_PROJECT_OWNER="fixture"
KIT_PROJECT_NUMBER="1"
ENV
F="$KIT_ROOT/evals/fixtures/board"; errors=""

o1="$(KIT_BOARD_FIXTURE="$F/matches.json" "$BIN/board-check.sh" --write 2>&1)"; r1=$?
[ "$r1" = 0 ] || errors="$errors matching-board-refused"
ids="$(grep -c '^KIT_' "$KIT_BOARD_ENV_FILE" 2>/dev/null || echo 0)"
[ "$ids" = 10 ] || errors="$errors board.env-has-$ids-IDs"
h1="$(shasum "$KIT_BOARD_ENV_FILE" | cut -d' ' -f1)"

o2="$(KIT_BOARD_FIXTURE="$F/mismatches.json" "$BIN/board-check.sh" --write 2>&1)"; r2=$?
[ "$r2" = 1 ] || errors="$errors mismatching-board-exit-$r2"
for expected in "board option In Testing.*missing" "board option Todo.*surplus" "FAIL  order" "label owner:engineer-c.*missing"; do
  printf '%s' "$o2" | grep -qE "$expected" || errors="$errors not-detected:'$expected'"
done
h2="$(shasum "$KIT_BOARD_ENV_FILE" | cut -d' ' -f1)"
[ "$h1" = "$h2" ] || errors="$errors board.env-changed-despite-FAIL"

o3="$(KIT_BOARD_FIXTURE="$F/github-standard.json" "$BIN/board-check.sh" 2>&1)"; r3=$?
n3="$(printf '%s' "$o3" | grep -c '^FAIL' || true)"

observe "matching → exit $r1, board.env $ids IDs · mismatching → exit $r2, $(printf '%s' "$o2" | grep -c '^FAIL') FAIL, board.env unchanged · the GitHub default (Todo/In Progress/Done) → exit $r3, $n3 FAIL${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ] && [ "$r3" = 1 ]
