#!/usr/bin/env bash
# Richtet ein GitHub Project und das Repo fuer das Statusmodell aus kit.env ein.
#
#   bin/board-setup.sh            Board-Optionen setzen, Project mit Repo verknuepfen, Labels anlegen
#   bin/board-setup.sh --force    auch wenn schon Tickets auf dem Board liegen
#   bin/board-setup.sh --labels-only   nur die Repo-Labels anlegen (bestehendes Board, Optionen passen schon)
#
# ACHTUNG: Das Setzen der Optionen ERSETZT die Optionen des Status-Feldes. Tickets, die schon
# einen Status tragen, verlieren ihn. Deshalb bricht das Skript ohne --force ab, sobald das
# Board Eintraege hat. Danach immer: bin/board-check.sh --write
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FORCE=0; LABELS_ONLY=0
case "${1:-}" in --force) FORCE=1 ;; --labels-only) LABELS_ONLY=1 ;; "") ;; *) die "unbekannte Option '$1'" ;; esac
# Labels braucht jeder Aufbau, das Board nur KIT_BOARD=github-project.
if [ "$LABELS_ONLY" = 0 ]; then
  [ "$KIT_BOARD" = "github-project" ] || die "KIT_BOARD ist '$KIT_BOARD', nicht github-project. Ohne Board: bin/board-setup.sh --labels-only"
  case "$KIT_PROJECT_OWNER$KIT_PROJECT_NUMBER" in *UNKNOWN*) die "KIT_PROJECT_OWNER oder KIT_PROJECT_NUMBER steht auf UNKNOWN (kit.env)" ;; esac
fi
"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden"

if [ "$LABELS_ONLY" = 0 ]; then
PJ="$(gh project view "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --format json)" || die "Project nicht lesbar"
PID="$(printf '%s' "$PJ" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
ITEMS="$(printf '%s' "$PJ" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"]["totalCount"])')"
[ "$ITEMS" = 0 ] || [ "$FORCE" = 1 ] || die "Board hat $ITEMS Eintraege. Optionen ersetzen loescht deren Status. Nur mit --force."

FID="$(gh project field-list "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --format json \
  | python3 -c 'import json,sys; print(next(f["id"] for f in json.load(sys.stdin)["fields"] if f["name"]=="Status"))')" \
  || die "Feld 'Status' nicht gefunden"

# 1. Status-Optionen aus KIT_STATUS_MAP, in Reihenfolge der Vorwaertskante.
python3 - "$FID" "$KIT_STATUS_MAP" > "$(dirname "$BOARD_ENV")/.board-setup.json" <<'PY'
import json, sys
fid, smap = sys.argv[1], sys.argv[2]
colors = ["GRAY", "BLUE", "YELLOW", "ORANGE", "ORANGE", "PURPLE", "PURPLE", "GREEN"]
opts = [{"name": name, "color": colors[min(i, len(colors) - 1)], "description": key}
        for i, (key, name) in enumerate(l.split("|", 1) for l in smap.strip().splitlines() if "|" in l)]
q = """mutation($f:ID!,$o:[ProjectV2SingleSelectFieldOptionInput!]!){
  updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:$o}){
    projectV2Field { ... on ProjectV2SingleSelectField { options { name } } } } }"""
print(json.dumps({"query": q, "variables": {"f": fid, "o": opts}}))
PY
SETUP_JSON="$(dirname "$BOARD_ENV")/.board-setup.json"
RES="$(gh api graphql --input "$SETUP_JSON" 2>&1)"; RC=$?; rm -f "$SETUP_JSON"
[ "$RC" = 0 ] || die "Optionen nicht gesetzt: $RES"
echo "Status-Optionen: $(printf '%s' "$RES" | python3 -c 'import json,sys; print(" → ".join(o["name"] for o in json.load(sys.stdin)["data"]["updateProjectV2Field"]["projectV2Field"]["options"]))')"

# 2. Project mit dem Repo verknuepfen (idempotent: bereits verknuepft ist kein Fehler).
LINK="$(gh project link "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --repo "$KIT_REPO" 2>&1)" \
  && echo "verknuepft mit $KIT_REPO" \
  || case "$LINK" in *already*) echo "bereits verknuepft mit $KIT_REPO" ;; *) die "Verknuepfen gescheitert: $LINK" ;; esac

fi

# 3. Labels. --force aktualisiert ein vorhandenes Label, statt abzubrechen.
mk() { gh label create "$1" --repo "$KIT_REPO" --color "$2" --description "$3" --force > /dev/null && echo "Label $1"; }
printf '%s\n' "$KIT_STATUS_MAP" | grep '|' | while IFS='|' read -r key name; do
  [ "$key" = "done" ] || mk "$KIT_LABEL_PREFIX$key" "ededed" "Spiegel des Board-Status '$name' — nur bin/status.sh setzt es"
done
for r in engineer-a engineer-b qa-ruthless simplicity-reviewer security-engineer acceptance-tester; do
  mk "$KIT_OWNER_PREFIX$r" "c5def5" "haelt das Ticket — nur bin/status.sh und bin/claim.sh setzen es"
done
mk "$KIT_SPRINT_LABEL" "0e8a16" "Ticket gehoert zum aktiven Sprint"

echo "Fertig. Jetzt: bin/board-check.sh --write"
