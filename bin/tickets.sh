#!/usr/bin/env bash
# Ticket-Backend. Genau EINE Stelle im Kit spricht mit dem Ticketsystem.
#
#   list <label>              Ticketnummern (offen) mit diesem Label
#   sprint                    JSON: offene Tickets mit Sprint-Label (number,title,labels)
#   labels <nr>               Labels, eines je Zeile
#   add-label <nr> <label>    · rm-label <nr> <label>
#   assignees <nr>            · unassign <nr> <wer>
#   comment <nr> <text>       · comments <nr>   (JSON-Liste der Kommentartexte)
#   title <nr>                · close <nr>
#   pr <nr>                   "<pr-nummer> <head-sha8>" des verknuepften PRs, sonst Exit 1
#   pr-comments <pr>          JSON-Liste der Kommentartexte
#   pr-checks <pr>            Exit 0 nur wenn alle Checks gruen
#   pr-merge <pr>             Squash-Merge
#   pr-state <pr>             "<STATE> <merge-sha8|->"
#   board-set <nr> <option-id> [<name>]  Status-Feld setzen; mit <name> wird zurueckgelesen
#
# KIT_ISSUE_BACKEND=gh   -> echtes GitHub via gh
# KIT_ISSUE_BACKEND=file -> lokale JSON-Datei, fuer Evals und Trockenlaeufe
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CMD="${1:-}"; shift || true
[ -n "$CMD" ] || die "Aufruf: bin/tickets.sh <befehl> …"

FILE="${KIT_ISSUE_FILE:-$KIT_ROOT/.kit-issues.json}"
case "$FILE" in /*) ;; *) FILE="$KIT_ROOT/$FILE" ;; esac

file_backend() {
  python3 - "$FILE" "$KIT_SPRINT_LABEL" "$CMD" "$@" <<'PY'
import fcntl, json, os, sys
path, sprint_label, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]

# Eine Sperre um Lesen+Schreiben: neun Sessions duerfen sich hier nicht ueberholen.
lock = open(path + ".lock", "w")
fcntl.flock(lock, fcntl.LOCK_EX)
db = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        db = json.load(fh)

def issue(n):
    i = db.setdefault(str(n), {})
    for k, v in (("title", ""), ("labels", []), ("assignees", []), ("comments", []), ("state", "open")):
        i.setdefault(k, v)
    return i

def pr_of(prnr):
    for i in db.values():
        p = i.get("pr")
        if p and str(p.get("number")) == str(prnr):
            return p
    sys.exit(1)

def save():
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(db, fh, indent=2, sort_keys=True, ensure_ascii=False)
    os.replace(tmp, path)

if cmd == "list":
    for n, i in sorted(db.items(), key=lambda kv: int(kv[0])):
        if args[0] in i.get("labels", []) and i.get("state", "open") == "open":
            print(n)
elif cmd == "sprint":
    out = [{"number": int(n), "title": i.get("title", ""), "labels": [{"name": l} for l in i.get("labels", [])]}
           for n, i in sorted(db.items(), key=lambda kv: int(kv[0]))
           if sprint_label in i.get("labels", []) and i.get("state", "open") == "open"]
    print(json.dumps(out))
elif cmd == "labels":
    print("\n".join(issue(args[0])["labels"]))
elif cmd == "assignees":
    print("\n".join(issue(args[0])["assignees"]))
elif cmd == "title":
    print(issue(args[0])["title"])
elif cmd == "comments":
    print(json.dumps(issue(args[0])["comments"]))
elif cmd == "add-label":
    i = issue(args[0])
    if args[1] not in i["labels"]:
        i["labels"] = sorted(i["labels"] + [args[1]])
    save()
elif cmd == "rm-label":
    i = issue(args[0]); i["labels"] = [l for l in i["labels"] if l != args[1]]; save()
elif cmd == "unassign":
    i = issue(args[0]); i["assignees"] = [a for a in i["assignees"] if a != args[1]]; save()
elif cmd == "comment":
    issue(args[0])["comments"].append(args[1]); save()
elif cmd == "close":
    issue(args[0])["state"] = "closed"; save()
elif cmd == "board-set":
    if os.environ.get("KIT_FAKE_BOARD_FAIL"):
        sys.exit("FEHLER: Board-Schreibzugriff fehlgeschlagen (KIT_FAKE_BOARD_FAIL, nur Evals)")
    issue(args[0])["board"] = args[1]; save()
elif cmd == "pr":
    p = issue(args[0]).get("pr")
    if not p:
        sys.exit(1)
    print(p["number"], p["head"][:8])
elif cmd == "pr-comments":
    print(json.dumps(pr_of(args[0]).get("comments", [])))
elif cmd == "pr-checks":
    c = pr_of(args[0]).get("checks", "pending")
    print("checks:", c)
    sys.exit(0 if c == "pass" else 8)
elif cmd == "pr-merge":
    p = pr_of(args[0]); p["state"] = "MERGED"; p["merge"] = "f11e0000"; save()
elif cmd == "pr-state":
    p = pr_of(args[0]); print(p.get("state", "OPEN"), p.get("merge", "-"))
else:
    sys.exit("FEHLER: unbekannter Befehl '%s'" % cmd)
PY
}

gh_backend() {
  case "$CMD" in
    list)        gh issue list --repo "$KIT_REPO" --state open --label "$1" --json number -q '.[].number' ;;
    sprint)      gh issue list --repo "$KIT_REPO" --state open --label "$KIT_SPRINT_LABEL" --json number,title,labels --limit 50 ;;
    labels)      gh issue view "$1" --repo "$KIT_REPO" --json labels -q '.labels[].name' ;;
    assignees)   gh issue view "$1" --repo "$KIT_REPO" --json assignees -q '.assignees[].login' ;;
    title)       gh issue view "$1" --repo "$KIT_REPO" --json title -q .title ;;
    comments)    gh issue view "$1" --repo "$KIT_REPO" --json comments -q '[.comments[].body]' ;;
    add-label)   gh issue edit "$1" --repo "$KIT_REPO" --add-label "$2" > /dev/null ;;
    rm-label)    gh issue edit "$1" --repo "$KIT_REPO" --remove-label "$2" > /dev/null ;;
    unassign)    gh issue edit "$1" --repo "$KIT_REPO" --remove-assignee "$2" > /dev/null ;;
    comment)     gh issue comment "$1" --repo "$KIT_REPO" --body "$2" > /dev/null ;;
    close)
      [ "$(gh issue view "$1" --repo "$KIT_REPO" --json state -q .state)" = "CLOSED" ] \
        || gh issue close "$1" --repo "$KIT_REPO" > /dev/null ;;
    pr)
      local pr head
      pr="$(gh issue view "$1" --repo "$KIT_REPO" --json closedByPullRequestsReferences \
              -q '.closedByPullRequestsReferences[0].number // empty')"
      [ -n "$pr" ] || exit 1
      head="$(gh pr view "$pr" --repo "$KIT_REPO" --json headRefOid -q '.headRefOid[0:8]')"
      [ -n "$head" ] || exit 1
      echo "$pr $head" ;;
    pr-comments) gh pr view "$1" --repo "$KIT_REPO" --json comments -q '[.comments[].body]' ;;
    pr-checks)   gh pr checks "$1" --repo "$KIT_REPO" ;;
    pr-merge)    gh pr merge "$1" --repo "$KIT_REPO" --squash > /dev/null ;;
    pr-state)    gh pr view "$1" --repo "$KIT_REPO" --json state,mergeCommit -q '"\(.state) \(.mergeCommit.oid[0:8] // "-")"' ;;
    board-set)
      : "${KIT_PROJECT_ID:?board.env fehlt — erst bin/board-check.sh --write}"
      : "${KIT_STATUS_FIELD_ID:?board.env fehlt — erst bin/board-check.sh --write}"
      local content item
      content="$(gh issue view "$1" --repo "$KIT_REPO" --json id -q .id)"
      # addProjectV2ItemById ist idempotent: liegt das Issue schon auf dem Board, kommt die
      # vorhandene Item-ID zurueck, es entsteht kein Duplikat.
      item="$(gh api graphql -f query='
        mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p, contentId:$c}){ item { id } } }' \
        -f p="$KIT_PROJECT_ID" -f c="$content" -q '.data.addProjectV2ItemById.item.id')"
      [ -n "$item" ] || die "Board-Item fuer #$1 nicht bekommen — Zustand pruefen, nicht raten"
      gh project item-edit --id "$item" --project-id "$KIT_PROJECT_ID" \
        --field-id "$KIT_STATUS_FIELD_ID" --single-select-option-id "$2" > /dev/null
      # Zuruecklesen. Das Board ist die Wahrheit — ein stiller Fehlschlag darf sie nicht
      # verfaelschen. Einmal beobachtet (2026-09-10, erstes Item eines neuen Boards): Exit 0,
      # Wert nicht lesbar. Nicht reproduziert, Ursache UNKNOWN — deshalb gemessen statt geglaubt.
      [ -n "${3:-}" ] || return 0
      local got="" try
      for try in 1 2 3 4; do
        got="$(gh api graphql -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2Item {
                 fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue { name } } } } }' \
               -f id="$item" -q '.data.node.fieldValueByName.name // ""' 2>/dev/null || true)"
        [ "$got" = "$3" ] && return 0
        sleep 2
      done
      die "Board zeigt fuer #$1 '${got:-nichts}' statt '$3' nach 4 Leseversuchen — Label bleibt unveraendert" ;;
    *) die "unbekannter Befehl '$CMD'" ;;
  esac
}

case "$KIT_ISSUE_BACKEND" in
  gh)   gh_backend "$@" ;;
  file) file_backend "$@" ;;
  *)    die "KIT_ISSUE_BACKEND muss 'gh' oder 'file' sein, ist '$KIT_ISSUE_BACKEND'" ;;
esac
