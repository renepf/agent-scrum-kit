#!/usr/bin/env bash
CASE_DESC="with a board: status.sh sets the board first and reads it back, the label after; without a board no board call"
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
errors=""

# A) planned -> in-progress with a board
"$BIN/status.sh" 7 in-progress "eval" > /dev/null 2>&1 || errors="$errors A:exit"
board_a="$(fake_gh_get 7 board)"; label_a="$(fake_gh_get 7 labels)"
z_board="$(grep -n "item-edit PVTI_7 o-inprogress" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
z_label="$(grep -n "issue edit 7 --add-label status:in-progress" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
[ "$board_a" = "o-inprogress" ] || errors="$errors A:board=$board_a"
# Since the owner: model, ownership hangs on the ticket as a label of its own (protocols/LOOP.md 1).
[ "$label_a" = "status:in-progress owner:engineer-a" ] || errors="$errors A:label=$label_a"
z_read="$(grep -n "api graphql readback PVTI_7" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
[ -n "$z_board" ] && [ -n "$z_read" ] && [ -n "$z_label" ] && [ "$z_board" -lt "$z_read" ] && [ "$z_read" -lt "$z_label" ] \
  || errors="$errors A:order(board=${z_board:-never},readback=${z_read:-never},label=${z_label:-never})"

# B) in-testing -> done: the board on done, no status label, the issue closed.
#    product-owner instead of merge-gate: done without 'PO OK' is locked since "the PO has the last word".
: > "$FAKE_GH_LOG"
KIT_ROLE=product-owner "$BIN/status.sh" 8 done "eval" > /dev/null 2>&1 || errors="$errors B:exit"
board_b="$(fake_gh_get 8 board)"; label_b="$(fake_gh_get 8 labels)"; state_b="$(fake_gh_get 8 state)"
z_board="$(grep -n "item-edit PVTI_8 o-done" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
z_close="$(grep -n "issue close 8" "$FAKE_GH_LOG" | head -1 | cut -d: -f1)"
[ "$board_b" = "o-done" ] || errors="$errors B:board=$board_b"
[ -z "$label_b" ] || errors="$errors B:label=$label_b"
[ "$state_b" = "CLOSED" ] || errors="$errors B:state=$state_b"
[ -n "$z_board" ] && [ -n "$z_close" ] && [ "$z_board" -lt "$z_close" ] || errors="$errors B:order(board=${z_board:-never},close=${z_close:-never})"

# C) without a board (KIT_BOARD=none): the labels are the truth, not a single board call
: > "$FAKE_GH_LOG"
cp "$SANDBOX/kit.env" "$SANDBOX/noboard.env"; echo 'KIT_BOARD="none"' >> "$SANDBOX/noboard.env"
KIT_ENV_FILE="$SANDBOX/noboard.env" "$BIN/status.sh" 9 in-progress "eval" > /dev/null 2>&1 || errors="$errors C:exit"
board_calls="$(grep -cE 'graphql|item-edit' "$FAKE_GH_LOG" || true)"
[ "$board_calls" = 0 ] || errors="$errors C:board-aufrufe=$board_calls"
[ "$(fake_gh_get 9 labels)" = "status:in-progress owner:engineer-a" ] || errors="$errors C:label=$(fake_gh_get 9 labels)"

observe "A: board o-inprogress before the label · B: board o-done before close, 0 labels · C: without a board $board_calls board calls${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
