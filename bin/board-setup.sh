#!/usr/bin/env bash
# Sets up a GitHub Project and the repo for the status model from kit.env.
#
#   bin/board-setup.sh            set the board options, link the project to the repo, create the labels
#   bin/board-setup.sh --force    even when tickets already lie on the board
#   bin/board-setup.sh --labels-only   only create the repo labels (existing board, options already fit)
#
# CAUTION: setting the options REPLACES the options of the status field. Tickets that already carry
# a status lose it. That is why the script aborts without --force as soon as the board has entries.
# Afterwards always: bin/board-check.sh --write
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FORCE=0; LABELS_ONLY=0
case "${1:-}" in --force) FORCE=1 ;; --labels-only) LABELS_ONLY=1 ;; "") ;; *) die "unknown option '$1'" ;; esac
# Labels are needed by every setup, the board only by KIT_BOARD=github-project.
if [ "$LABELS_ONLY" = 0 ]; then
  [ "$KIT_BOARD" = "github-project" ] || die "KIT_BOARD is '$KIT_BOARD', not github-project. Without a board: bin/board-setup.sh --labels-only"
  case "$KIT_PROJECT_OWNER$KIT_PROJECT_NUMBER" in *UNKNOWN*) die "KIT_PROJECT_OWNER or KIT_PROJECT_NUMBER still says UNKNOWN (kit.env)" ;; esac
fi
"$BIN_DIR/preflight.sh" > /dev/null || die "preflight failed — stop and report"

if [ "$LABELS_ONLY" = 0 ]; then
PJ="$(gh project view "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --format json)" || die "project not readable"
PID="$(printf '%s' "$PJ" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
ITEMS="$(printf '%s' "$PJ" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"]["totalCount"])')"
[ "$ITEMS" = 0 ] || [ "$FORCE" = 1 ] || die "the board has $ITEMS entries. Replacing the options deletes their status. Only with --force."

FID="$(gh project field-list "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --format json \
  | python3 -c 'import json,sys; print(next(f["id"] for f in json.load(sys.stdin)["fields"] if f["name"]=="Status"))')" \
  || die "field 'Status' not found"

# 1. Status options from KIT_STATUS_MAP, in the order of the forward edge.
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
[ "$RC" = 0 ] || die "options not set: $RES"
echo "status options: $(printf '%s' "$RES" | python3 -c 'import json,sys; print(" → ".join(o["name"] for o in json.load(sys.stdin)["data"]["updateProjectV2Field"]["projectV2Field"]["options"]))')"

# 2. Link the project to the repo (idempotent: already linked is not an error).
LINK="$(gh project link "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --repo "$KIT_REPO" 2>&1)" \
  && echo "linked to $KIT_REPO" \
  || case "$LINK" in *already*) echo "already linked to $KIT_REPO" ;; *) die "linking failed: $LINK" ;; esac

fi

# 3. Labels. --force updates an existing label instead of aborting.
mk() { gh label create "$1" --repo "$KIT_REPO" --color "$2" --description "$3" --force > /dev/null && echo "label $1"; }
printf '%s\n' "$KIT_STATUS_MAP" | grep '|' | while IFS='|' read -r key name; do
  [ "$key" = "done" ] || mk "$KIT_LABEL_PREFIX$key" "ededed" "mirror of the board status '$name' — only bin/status.sh sets it"
done
for r in engineer-a engineer-b qa-ruthless simplicity-reviewer security-engineer acceptance-tester; do
  mk "$KIT_OWNER_PREFIX$r" "c5def5" "holds the ticket — only bin/status.sh and bin/claim.sh set it"
done
mk "$KIT_SPRINT_LABEL" "0e8a16" "ticket belongs to the active sprint"

echo "Done. Now: bin/board-check.sh --write"
