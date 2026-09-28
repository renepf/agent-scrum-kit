#!/usr/bin/env bash
CASE_DESC="if the board call fails or the board shows nothing afterwards, the label stays and status.sh aborts loudly"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
# The reviewing engineer moves rfr → in-review. The tickets carry no comment history, so no engineer
# counts as their builder — the four-eyes gate lets engineer-b through and the board is what fails.
export KIT_ROLE=engineer-b

fake_gh '{
 "21": {"labels": ["status:rfr"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-rfr"},
 "22": {"labels": ["status:rfr"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-rfr"},
 "23": {"labels": ["status:rfr"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-rfr"}
}'
errors=""; report=""

# After a failure NOTHING on the ticket may have changed: no label, no
# comment, no board value, no chat entry, and no write call after the error.
check_case() {
  local case_name="$1" nr="$2" rc="$3" out="$4"
  local chat_before="$5"
  [ "$rc" != 0 ] || errors="$errors $case_name:exit0"
  [ "$(fake_gh_get "$nr" labels)" = "status:rfr" ] || errors="$errors $case_name:label=$(fake_gh_get "$nr" labels)"
  [ "$(fake_gh_get "$nr" board)" = "o-rfr" ] || errors="$errors $case_name:board=$(fake_gh_get "$nr" board)"
  [ -z "$(fake_gh_get "$nr" comments)" ] || errors="$errors $case_name:comment"
  grep -qE "issue (edit|comment|close) $nr" "$FAKE_GH_LOG" && errors="$errors $case_name:schreibaufruf-nach-errors"
  [ "$(chat_lines)" = "$chat_before" ] || errors="$errors $case_name:chat-entry"
  case "$out" in *[Bb]oard*) ;; *) errors="$errors $case_name:message-does-not-name-the-board" ;; esac
  report="$report $case_name:rc=$rc"
}
chat_lines() { cat "$SANDBOX"/sprints/*/chat/*.md 2>/dev/null | wc -l | tr -d ' '; }

# A) addProjectV2ItemById fails
: > "$FAKE_GH_LOG"; c="$(chat_lines)"
out="$(FAKE_GH_FAIL=graphql "$BIN/status.sh" 21 in-review "eval" 2>&1)"; rc=$?
check_case A 21 "$rc" "$out" "$c"

# B) project item-edit fails
: > "$FAKE_GH_LOG"; c="$(chat_lines)"
out="$(FAKE_GH_FAIL=item-edit "$BIN/status.sh" 22 in-review "eval" 2>&1)"; rc=$?
check_case B 22 "$rc" "$out" "$c"

# C) no option id for the target state: abort before anything is written
: > "$FAKE_GH_LOG"; c="$(chat_lines)"
grep -v '^KIT_OPTION_IN_REVIEW=' "$KIT_BOARD_ENV_FILE" > "$SANDBOX/gappy.env"
out="$(KIT_BOARD_ENV_FILE="$SANDBOX/gappy.env" "$BIN/status.sh" 23 in-review "eval" 2>&1)"; rc=$?
check_case C 23 "$rc" "$out" "$c"
grep -qE 'graphql|item-edit' "$FAKE_GH_LOG" && errors="$errors C:board-call-despite-a-missing-option"

# D) item-edit reports success but the board shows nothing: the read-back must abort
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["24"]={"labels":["status:rfr"],"assignees":[],"state":"OPEN","comments":[],"board":"o-rfr"}; json.dump(d,open(p,"w"))' "$FAKE_GH_STATE"
: > "$FAKE_GH_LOG"; c="$(chat_lines)"
out="$(FAKE_GH_FAIL=readback "$BIN/status.sh" 24 in-review "eval" 2>&1)"; rc=$?
# D may have run item-edit (the value then stands on the board) — what is checked is that nothing
# was written afterwards. Hence a check of its own instead of check_case().
[ "$rc" != 0 ] || errors="$errors D:exit0"
[ "$(fake_gh_get 24 labels)" = "status:rfr" ] || errors="$errors D:label=$(fake_gh_get 24 labels)"
[ -z "$(fake_gh_get 24 comments)" ] || errors="$errors D:comment"
grep -qE "issue (edit|comment|close) 24" "$FAKE_GH_LOG" && errors="$errors D:write-call-after-the-error"
[ "$(grep -c 'readback PVTI_24' "$FAKE_GH_LOG")" = 4 ] || errors="$errors D:$(grep -c 'readback PVTI_24' "$FAKE_GH_LOG")-read-attempts-instead-of-4"
case "$out" in *[Bb]oard*) ;; *) errors="$errors D:message-does-not-name-the-board" ;; esac
report="$report D:rc=$rc"

observe "A a graphql error, B an item-edit error, C a missing option id, D an empty read-back:$report · $([ -z "$errors" ] && echo "label, board, comment and chat unchanged" || echo "ERRORS:$errors")"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
