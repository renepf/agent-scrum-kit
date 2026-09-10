#!/usr/bin/env bash
CASE_DESC="mit Board: status.sh setzt Board zuerst, Label danach; ohne Board kein Board-Aufruf"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=engineer-a

fake_gh '{
 "7": {"labels": ["status:planned"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-planned"},
 "8": {"labels": ["status:in-testing"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-intesting"},
 "9": {"labels": ["status:planned"], "assignees": [], "state": "OPEN", "comments": [], "board": null}
}'
fehler=""

# A) planned -> in-progress mit Board
KIT_ENV_FILE="$SANDBOX/board.env" "$BIN/status.sh" 7 in-progress "eval" > /dev/null 2>&1 || fehler="$fehler A:exit"
board_a="$(fake_gh_get 7 board)"; label_a="$(fake_gh_get 7 labels)"
z_board="$(grep -n "item-edit PVTI_7 o-inprogress" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
z_label="$(grep -n "issue edit 7 --add-label status:in-progress" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
[ "$board_a" = "o-inprogress" ] || fehler="$fehler A:board=$board_a"
[ "$label_a" = "status:in-progress" ] || fehler="$fehler A:label=$label_a"
[ -n "$z_board" ] && [ -n "$z_label" ] && [ "$z_board" -lt "$z_label" ] || fehler="$fehler A:reihenfolge(board=${z_board:-nie},label=${z_label:-nie})"

# B) in-testing -> done: Board auf done, kein Status-Label, Issue geschlossen
: > "$FAKE_GH_LOG"
KIT_ENV_FILE="$SANDBOX/board.env" KIT_ROLE=merge-gate "$BIN/status.sh" 8 done "eval" > /dev/null 2>&1 || fehler="$fehler B:exit"
board_b="$(fake_gh_get 8 board)"; label_b="$(fake_gh_get 8 labels)"; state_b="$(fake_gh_get 8 state)"
z_board="$(grep -n "item-edit PVTI_8 o-done" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
z_close="$(grep -n "issue close 8" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
[ "$board_b" = "o-done" ] || fehler="$fehler B:board=$board_b"
[ -z "$label_b" ] || fehler="$fehler B:label=$label_b"
[ "$state_b" = "CLOSED" ] || fehler="$fehler B:state=$state_b"
[ -n "$z_board" ] && [ -n "$z_close" ] && [ "$z_board" -lt "$z_close" ] || fehler="$fehler B:reihenfolge(board=${z_board:-nie},close=${z_close:-nie})"

# C) ohne KIT_PROJECT_ID: Labels sind die Wahrheit, kein einziger Board-Aufruf
: > "$FAKE_GH_LOG"
grep -v '^KIT_PROJECT_ID=' "$SANDBOX/board.env" > "$SANDBOX/noboard.env"
echo 'KIT_PROJECT_ID=""' >> "$SANDBOX/noboard.env"
KIT_ENV_FILE="$SANDBOX/noboard.env" "$BIN/status.sh" 9 in-progress "eval" > /dev/null 2>&1 || fehler="$fehler C:exit"
board_aufrufe="$(grep -cE 'graphql|item-edit' "$FAKE_GH_LOG" || true)"
[ "$board_aufrufe" = 0 ] || fehler="$fehler C:board-aufrufe=$board_aufrufe"
[ "$(fake_gh_get 9 labels)" = "status:in-progress" ] || fehler="$fehler C:label=$(fake_gh_get 9 labels)"

observe "A: Board o-inprogress vor Label · B: Board o-done vor close, 0 Labels · C: ohne Board $board_aufrufe Board-Aufrufe${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
