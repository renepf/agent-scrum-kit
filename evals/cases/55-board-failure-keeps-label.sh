#!/usr/bin/env bash
CASE_DESC="scheitert der Board-Aufruf, bleibt das Label stehen und status.sh bricht laut ab"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=qa-ruthless

fake_gh '{
 "21": {"labels": ["status:rfr"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-rfr"},
 "22": {"labels": ["status:rfr"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-rfr"},
 "23": {"labels": ["status:rfr"], "assignees": [], "state": "OPEN", "comments": [], "board": "o-rfr"}
}'
fehler=""; bericht=""

# Nach einem Fehlschlag darf sich am Ticket NICHTS geaendert haben: kein Label, kein
# Kommentar, kein Board-Wert, kein Chat-Eintrag, und kein Schreibaufruf nach dem Fehler.
pruefe() {
  local fall="$1" nr="$2" rc="$3" out="$4"
  local chat_vorher="$5"
  [ "$rc" != 0 ] || fehler="$fehler $fall:exit0"
  [ "$(fake_gh_get "$nr" labels)" = "status:rfr" ] || fehler="$fehler $fall:label=$(fake_gh_get "$nr" labels)"
  [ "$(fake_gh_get "$nr" board)" = "o-rfr" ] || fehler="$fehler $fall:board=$(fake_gh_get "$nr" board)"
  [ -z "$(fake_gh_get "$nr" comments)" ] || fehler="$fehler $fall:kommentar"
  grep -qE "issue (edit|comment|close) $nr" "$FAKE_GH_LOG" && fehler="$fehler $fall:schreibaufruf-nach-fehler"
  [ "$(chat_zeilen)" = "$chat_vorher" ] || fehler="$fehler $fall:chat-eintrag"
  case "$out" in *Board*) ;; *) fehler="$fehler $fall:meldung-nennt-board-nicht" ;; esac
  bericht="$bericht $fall:rc=$rc"
}
chat_zeilen() { cat "$SANDBOX"/sprints/*/chat/*.md 2>/dev/null | wc -l | tr -d ' '; }

# A) addProjectV2ItemById scheitert
: > "$FAKE_GH_LOG"; c="$(chat_zeilen)"
out="$(FAKE_GH_FAIL=graphql KIT_ENV_FILE="$SANDBOX/board.env" "$BIN/status.sh" 21 in-review "eval" 2>&1)"; rc=$?
pruefe A 21 "$rc" "$out" "$c"

# B) project item-edit scheitert
: > "$FAKE_GH_LOG"; c="$(chat_zeilen)"
out="$(FAKE_GH_FAIL=item-edit KIT_ENV_FILE="$SANDBOX/board.env" "$BIN/status.sh" 22 in-review "eval" 2>&1)"; rc=$?
pruefe B 22 "$rc" "$out" "$c"

# C) keine Options-ID fuer den Zielzustand: Abbruch, bevor irgendetwas geschrieben wird
: > "$FAKE_GH_LOG"; c="$(chat_zeilen)"
sed 's/ in-review=o-inreview//' "$SANDBOX/board.env" > "$SANDBOX/lueckig.env"
out="$(KIT_ENV_FILE="$SANDBOX/lueckig.env" "$BIN/status.sh" 23 in-review "eval" 2>&1)"; rc=$?
pruefe C 23 "$rc" "$out" "$c"
grep -qE 'graphql|item-edit' "$FAKE_GH_LOG" && fehler="$fehler C:board-aufruf-trotz-fehlender-option"

observe "A graphql-Fehler, B item-edit-Fehler, C fehlende Options-ID:$bericht · $([ -z "$fehler" ] && echo "Label, Board, Kommentar, Chat unveraendert" || echo "FEHLER:$fehler")"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
