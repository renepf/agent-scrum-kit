#!/usr/bin/env bash
# Ticket-Backend. Genau EINE Stelle im Kit spricht mit dem Ticketsystem.
#
#   bin/tickets.sh list <status>          # Ticketnummern mit diesem Status
#   bin/tickets.sh labels <nr>            # alle Labels des Tickets, eines je Zeile
#   bin/tickets.sh add-label <nr> <label>
#   bin/tickets.sh rm-label <nr> <label>
#   bin/tickets.sh assignees <nr>
#   bin/tickets.sh assign <nr> <wer>
#   bin/tickets.sh unassign <nr> <wer>
#   bin/tickets.sh comment <nr> <text>
#   bin/tickets.sh title <nr>
#   bin/tickets.sh close <nr>
#   bin/tickets.sh set-board <nr> <zustand>   # no-op ohne KIT_PROJECT_ID
#
# KIT_ISSUE_BACKEND=gh   -> echtes GitHub via gh
# KIT_ISSUE_BACKEND=file -> lokale JSON-Datei, fuer Evals und Trockenlaeufe
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CMD="${1:-}"; shift || true
[ -n "$CMD" ] || die "Aufruf: bin/tickets.sh <befehl> …"

FILE="${KIT_ISSUE_FILE:-$KIT_ROOT/.kit-issues.json}"
case "$FILE" in /*) ;; *) FILE="$KIT_ROOT/$FILE" ;; esac

file_backend() {
  python3 - "$FILE" "$CMD" "$@" <<'PY'
import json, os, sys
path, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
db = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        db = json.load(fh)

def issue(n):
    return db.setdefault(str(n), {"title": "", "labels": [], "assignees": [], "comments": []})

def save():
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(db, fh, indent=2, sort_keys=True, ensure_ascii=False)
    os.replace(tmp, path)

if cmd == "list":
    want = args[0]
    for n, i in sorted(db.items(), key=lambda kv: int(kv[0])):
        if want in i.get("labels", []):
            print(n)
elif cmd == "labels":
    for l in issue(args[0]).get("labels", []):
        print(l)
elif cmd == "assignees":
    for a in issue(args[0]).get("assignees", []):
        print(a)
elif cmd == "title":
    print(issue(args[0]).get("title", ""))
elif cmd == "add-label":
    i = issue(args[0])
    if args[1] not in i["labels"]:
        i["labels"].append(args[1]); i["labels"].sort()
    save()
elif cmd == "rm-label":
    i = issue(args[0])
    i["labels"] = [l for l in i["labels"] if l != args[1]]
    save()
elif cmd == "assign":
    i = issue(args[0])
    if args[1] not in i["assignees"]:
        i["assignees"].append(args[1])
    save()
elif cmd == "unassign":
    i = issue(args[0])
    i["assignees"] = [a for a in i["assignees"] if a != args[1]]
    save()
elif cmd == "comment":
    issue(args[0])["comments"].append(args[1])
    save()
elif cmd == "close":
    issue(args[0])["closed"] = True
    save()
elif cmd == "set-board":
    # Das Datei-Backend hat kein Board. Die Label-Spalte ist hier die ganze Wahrheit.
    pass
else:
    sys.exit("FEHLER: unbekannter Befehl '%s'" % cmd)
PY
}

# Board-Status setzen. Ohne KIT_PROJECT_ID: nichts zu tun, Labels sind die Wahrheit.
gh_set_board() {
  [ -n "${KIT_PROJECT_ID:-}" ] || return 0
  local nr="$1" state="$2" opt="" pair content item
  for pair in ${KIT_STATUS_OPTIONS:-}; do
    [ "${pair%%=*}" = "$state" ] && opt="${pair#*=}"
  done
  [ -n "$opt" ] || die "KIT_STATUS_OPTIONS kennt keine Options-ID fuer '$state'"
  [ -n "${KIT_STATUS_FIELD_ID:-}" ] || die "KIT_STATUS_FIELD_ID fehlt in kit.env"
  content="$(gh issue view "$nr" --repo "$KIT_REPO" --json id -q .id)" || return 1
  # addProjectV2ItemById ist idempotent: liegt das Issue schon auf dem Board, kommt die
  # vorhandene Item-ID zurueck.
  item="$(gh api graphql -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' \
          -f p="$KIT_PROJECT_ID" -f c="$content" -q '.data.addProjectV2ItemById.item.id')" || return 1
  [ -n "$item" ] || return 1
  gh project item-edit --id "$item" --project-id "$KIT_PROJECT_ID" \
    --field-id "$KIT_STATUS_FIELD_ID" --single-select-option-id "$opt" > /dev/null
}

gh_backend() {
  case "$CMD" in
    list)      gh issue list --repo "$KIT_REPO" --state open --label "$1" --json number -q '.[].number' ;;
    labels)    gh issue view "$1" --repo "$KIT_REPO" --json labels -q '.labels[].name' ;;
    assignees) gh issue view "$1" --repo "$KIT_REPO" --json assignees -q '.assignees[].login' ;;
    title)     gh issue view "$1" --repo "$KIT_REPO" --json title -q .title ;;
    add-label) gh issue edit "$1" --repo "$KIT_REPO" --add-label "$2" > /dev/null ;;
    rm-label)  gh issue edit "$1" --repo "$KIT_REPO" --remove-label "$2" > /dev/null ;;
    assign)    gh issue edit "$1" --repo "$KIT_REPO" --add-assignee "$2" > /dev/null ;;
    unassign)  gh issue edit "$1" --repo "$KIT_REPO" --remove-assignee "$2" > /dev/null ;;
    comment)   gh issue comment "$1" --repo "$KIT_REPO" --body "$2" > /dev/null ;;
    close)     gh issue view "$1" --repo "$KIT_REPO" --json state -q .state | grep -q CLOSED \
                 || gh issue close "$1" --repo "$KIT_REPO" > /dev/null ;;
    set-board) gh_set_board "$1" "$2" ;;
    *)         die "unbekannter Befehl '$CMD'" ;;
  esac
}

case "$KIT_ISSUE_BACKEND" in
  gh)   gh_backend "$@" ;;
  file) file_backend "$@" ;;
  *)    die "KIT_ISSUE_BACKEND muss 'gh' oder 'file' sein, ist '$KIT_ISSUE_BACKEND'" ;;
esac
