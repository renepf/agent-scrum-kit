#!/usr/bin/env bash
CASE_DESC="board-check erkennt fehlende, ueberzaehlige und falsch sortierte Optionen und fehlende Labels; schreibt board.env nur bei Erfolg"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
cat >> "$KIT_ENV_FILE" <<'ENV'
KIT_BOARD="github-project"
KIT_PROJECT_OWNER="fixture"
KIT_PROJECT_NUMBER="1"
ENV
F="$KIT_ROOT/evals/fixtures/board"; fehler=""

o1="$(KIT_BOARD_FIXTURE="$F/passt.json" "$BIN/board-check.sh" --write 2>&1)"; r1=$?
[ "$r1" = 0 ] || fehler="$fehler passendes-Board-abgelehnt"
ids="$(grep -c '^KIT_' "$KIT_BOARD_ENV_FILE" 2>/dev/null || echo 0)"
[ "$ids" = 10 ] || fehler="$fehler board.env-hat-$ids-IDs"
h1="$(shasum "$KIT_BOARD_ENV_FILE" | cut -d' ' -f1)"

o2="$(KIT_BOARD_FIXTURE="$F/passt-nicht.json" "$BIN/board-check.sh" --write 2>&1)"; r2=$?
[ "$r2" = 1 ] || fehler="$fehler falsches-Board-Exit-$r2"
for erwartet in "Board-Option In Testing.*fehlt" "Board-Option Todo.*ueberzaehlig" "FAIL  Reihenfolge" "Label owner:qa-ruthless.*fehlt"; do
  printf '%s' "$o2" | grep -qE "$erwartet" || fehler="$fehler nicht-erkannt:'$erwartet'"
done
h2="$(shasum "$KIT_BOARD_ENV_FILE" | cut -d' ' -f1)"
[ "$h1" = "$h2" ] || fehler="$fehler board.env-trotz-FAIL-geaendert"

o3="$(KIT_BOARD_FIXTURE="$F/github-standard.json" "$BIN/board-check.sh" 2>&1)"; r3=$?
n3="$(printf '%s' "$o3" | grep -c '^FAIL' || true)"

observe "passend → Exit $r1, board.env $ids IDs · falsch → Exit $r2, $(printf '%s' "$o2" | grep -c '^FAIL') FAIL, board.env unveraendert · GitHub-Standard (Todo/In Progress/Done) → Exit $r3, $n3 FAIL${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ] && [ "$r3" = 1 ]
