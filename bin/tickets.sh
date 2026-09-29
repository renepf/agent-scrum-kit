#!/usr/bin/env bash
# Ticket backend. Exactly ONE place in the kit talks to the ticket system.
#
#   list <label>              ticket numbers (open) carrying this label
#   sprint                    JSON: open tickets with the sprint label (number,title,labels)
#   labels <nr>               labels, one per line
#   add-label <nr> <label>    · rm-label <nr> <label>
#   assignees <nr>            · unassign <nr> <who>
#   comment <nr> <text>       · comments <nr>   (JSON list of the comment texts)
#   title <nr>                · close <nr>
#   body <nr>                 issue text (story and AC lines)
#   pr <nr>                   "<pr-number> <head-sha8>" of the linked PR, otherwise exit 1
#   pr-comments <pr>          JSON list of the comment texts
#   pr-files <pr>             changed files of the PR, one per line; on a rename the old path too
#   pr-checks <pr>            exit 0 only when every check is green
#   pr-merge <pr>             squash merge
#   pr-state <pr>             "<STATE> <merge-sha8|->"
#   board-set <nr> <option-id> [<name>]  set the status field; with <name> it is read back
#
# KIT_ISSUE_BACKEND=gh   -> real GitHub via gh
# KIT_ISSUE_BACKEND=file -> local JSON file, for evals and dry runs
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CMD="${1:-}"; shift || true
[ -n "$CMD" ] || die "usage: bin/tickets.sh <command> …"

FILE="${KIT_ISSUE_FILE:-$KIT_ROOT/.kit-issues.json}"
case "$FILE" in /*) ;; *) FILE="$KIT_ROOT/$FILE" ;; esac

file_backend() {
  python3 - "$FILE" "$KIT_SPRINT_LABEL" "$CMD" "$@" <<'PY'
import fcntl, json, os, sys
path, sprint_label, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]

# An I/O error ends in ONE line that names the file, never in a stack trace — the same
# standard the gates hold (case 98). A caller reads a trace as a crash, not as a state.
def io_die(what, err):
    print(f"ERROR: {what} {path}: {err}", file=sys.stderr)
    sys.exit(1)

# One lock around read+write: nine sessions must not overtake each other here.
try:
    lock = open(path + ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
except OSError as e:
    io_die("cannot lock", e)
db = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as fh:
            db = json.load(fh)
    except (OSError, ValueError) as e:
        io_die("cannot read", e)

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

if os.environ.get("KIT_FAKE_READ_FAIL") == cmd:
    sys.exit("ERROR: read '%s' failed (KIT_FAKE_READ_FAIL, evals only)" % cmd)

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
elif cmd == "body":
    print(issue(args[0]).get("body", ""))
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
        sys.exit("ERROR: board write failed (KIT_FAKE_BOARD_FAIL, evals only)")
    issue(args[0])["board"] = args[1]; save()
elif cmd == "pr":
    p = issue(args[0]).get("pr")
    if not p:
        sys.exit(1)
    print(p["number"], p["head"][:8])
elif cmd == "pr-comments":
    print(json.dumps(pr_of(args[0]).get("comments", [])))
elif cmd == "pr-files":
    print("\n".join(pr_of(args[0]).get("files", [])))
elif cmd == "pr-checks":
    c = pr_of(args[0]).get("checks", "pending")
    print("checks:", c)
    sys.exit(0 if c == "pass" else 8)
elif cmd == "pr-merge":
    p = pr_of(args[0]); p["state"] = "MERGED"; p["merge"] = "f11e0000"; save()
elif cmd == "pr-state":
    p = pr_of(args[0]); print(p.get("state", "OPEN"), p.get("merge", "-"))
else:
    sys.exit("ERROR: unknown command '%s'" % cmd)
PY
}

gh_backend() {
  case "$CMD" in
    list)        gh issue list --repo "$KIT_REPO" --state open --label "$1" --json number -q '.[].number' ;;
    sprint)      gh issue list --repo "$KIT_REPO" --state open --label "$KIT_SPRINT_LABEL" --json number,title,labels --limit 50 ;;
    labels)      gh issue view "$1" --repo "$KIT_REPO" --json labels -q '.labels[].name' ;;
    assignees)   gh issue view "$1" --repo "$KIT_REPO" --json assignees -q '.assignees[].login' ;;
    title)       gh issue view "$1" --repo "$KIT_REPO" --json title -q .title ;;
    body)        gh issue view "$1" --repo "$KIT_REPO" --json body -q .body ;;
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
              -q '[.closedByPullRequestsReferences[].number | tostring] | join(" ")')"
      [ -n "$pr" ] || exit 1
      # Two PRs closing the same ticket: which one counts would be a guess.
      case "$pr" in *" "*) echo "several linked PRs: $pr — exactly one closes the ticket" >&2; exit 1 ;; esac
      head="$(gh pr view "$pr" --repo "$KIT_REPO" --json headRefOid -q '.headRefOid[0:8]')"
      [ -n "$head" ] || exit 1
      echo "$pr $head" ;;
    pr-comments) gh pr view "$1" --repo "$KIT_REPO" --json comments -q '[.comments[].body]' ;;
    # Not 'gh pr diff --name-only': on a rename that names only the new path.
    pr-files)    gh api "repos/$KIT_REPO/pulls/$1/files" --paginate -q '.[] | .filename, (.previous_filename // empty)' ;;
    pr-checks)   gh pr checks "$1" --repo "$KIT_REPO" ;;
    pr-merge)    gh pr merge "$1" --repo "$KIT_REPO" --squash > /dev/null ;;
    pr-state)    gh pr view "$1" --repo "$KIT_REPO" --json state,mergeCommit -q '"\(.state) \(.mergeCommit.oid[0:8] // "-")"' ;;
    board-set)
      : "${KIT_PROJECT_ID:?board.env is missing — run bin/board-check.sh --write first}"
      : "${KIT_STATUS_FIELD_ID:?board.env is missing — run bin/board-check.sh --write first}"
      local content item
      content="$(gh issue view "$1" --repo "$KIT_REPO" --json id -q .id)"
      # addProjectV2ItemById is idempotent: if the issue is already on the board, the existing
      # item id comes back, no duplicate appears.
      item="$(gh api graphql -f query='
        mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p, contentId:$c}){ item { id } } }' \
        -f p="$KIT_PROJECT_ID" -f c="$content" -q '.data.addProjectV2ItemById.item.id')"
      [ -n "$item" ] || die "did not get a board item for #$1 — check the state, do not guess"
      gh project item-edit --id "$item" --project-id "$KIT_PROJECT_ID" \
        --field-id "$KIT_STATUS_FIELD_ID" --single-select-option-id "$2" > /dev/null
      # Read back. The board is the truth — a silent failure must not falsify it.
      # Observed once (2026-09-10, first item of a new board): exit 0, value not readable.
      # Not reproduced, cause UNKNOWN — hence measured instead of believed.
      [ -n "${3:-}" ] || return 0
      local got="" try
      for try in 1 2 3 4; do
        got="$(gh api graphql -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2Item {
                 fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue { name } } } } }' \
               -f id="$item" -q '.data.node.fieldValueByName.name // ""' 2>/dev/null || true)"
        [ "$got" = "$3" ] && return 0
        sleep 2
      done
      die "the board shows '${got:-nothing}' for #$1 instead of '$3' after 4 read attempts — the label stays unchanged" ;;
    *) die "unknown command '$CMD'" ;;
  esac
}

case "$KIT_ISSUE_BACKEND" in
  gh)   gh_backend "$@" ;;
  file) file_backend "$@" ;;
  *)    die "KIT_ISSUE_BACKEND must be 'gh' or 'file', it is '$KIT_ISSUE_BACKEND'" ;;
esac
