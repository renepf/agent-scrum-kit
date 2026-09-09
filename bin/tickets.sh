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
else:
    sys.exit("FEHLER: unbekannter Befehl '%s'" % cmd)
PY
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
    *)         die "unbekannter Befehl '$CMD'" ;;
  esac
}

case "$KIT_ISSUE_BACKEND" in
  gh)   gh_backend "$@" ;;
  file) file_backend "$@" ;;
  *)    die "KIT_ISSUE_BACKEND muss 'gh' oder 'file' sein, ist '$KIT_ISSUE_BACKEND'" ;;
esac
