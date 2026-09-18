#!/usr/bin/env bash
CASE_DESC="a refused transition writes nothing: no label, no board, no comment"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
cat >> "$KIT_ENV_FILE" <<'ENV'
KIT_BOARD="github-project"
ENV
printf 'KIT_PROJECT_ID="P"\nKIT_STATUS_FIELD_ID="F"\n' > "$KIT_BOARD_ENV_FILE"
for k in BACKLOG PLANNED IN_PROGRESS RFR IN_REVIEW RFT IN_TESTING DONE; do echo "KIT_OPTION_$k=\"opt-$k\"" >> "$KIT_BOARD_ENV_FILE"; done
sandbox_issue 9 '{"labels":["status:in-progress","owner:engineer-a"],"comments":["**Planned** — product-owner · eval · session `e`\n\nOWNS Revision 1: `src/**`"],"pr":{"number":90,"head":"cafecafe99","comments":[],"files":["src/a.py"]}}'

snap() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["9"], sort_keys=True))' "$SANDBOX/issues.json"; }
before="$(snap)"; errors=""

KIT_ROLE=engineer-b "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 && errors="$errors foreign-ownership-let-through"
KIT_ROLE=qa-ruthless "$BIN/status.sh" 9 rft x > /dev/null 2>&1 && errors="$errors edge-let-through"
KIT_ROLE=watchdog "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 && errors="$errors wrong-role-let-through"
after_rejection="$(snap)"
[ "$before" = "$after_rejection" ] || errors="$errors state-changed"

# The board write fails: the label must NOT change.
KIT_FAKE_BOARD_FAIL=1 KIT_ROLE=engineer-a "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 && errors="$errors board-error-ignored"
after_board_error="$(sandbox_labels 9)"
[ "$after_board_error" = "owner:engineer-a status:in-progress" ] || errors="$errors label-despite-board-error='$after_board_error'"

# Counter-check: without an error the same transition sets the board AND the label.
KIT_ROLE=engineer-a "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 || errors="$errors counter-check-failed"
board="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["9"].get("board","-"))' "$SANDBOX/issues.json")"
[ "$board" = "opt-RFR" ] || errors="$errors board='$board'"

observe "3 rejections, state byte-identical: $([ "$before" = "$after_rejection" ] && echo yes || echo NO) · board error → labels '$after_board_error' · counter-check → board=$board, labels '$(sandbox_labels 9)'${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
