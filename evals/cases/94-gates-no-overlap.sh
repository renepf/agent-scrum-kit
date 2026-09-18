#!/usr/bin/env bash
CASE_DESC="no overlap: planned, revise.sh and sprint-new.sh refuse OWNS that overlap an approved ticket of the same sprint"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
st() { KIT_ROLE="$1" "$BIN/status.sh" "$2" "$3" x 2>&1; }
in_sprint() { sandbox_issue "$1" '{"labels":["sprint:current"]}'; }
comment_count() { KIT_ROLE=product-owner "$BIN/tickets.sh" comments "$1" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }

# a) Glob pairs: separate only when a literal segment differs or a single file is not matched
while IFS='|' read -r a b soll; do
  [ -n "$a" ] || continue
  n=$((n + 1))
  printf '#a\t%s\n#b\t%s\n' "$a" "$b" | python3 "$BIN/gates.py" overlap > /dev/null 2>&1 && ist=separate || ist=overlaps
  [ "$ist" = "$soll" ] || fail "a:'$a'~'$b'=$ist"
done <<'TABELLE'
src/api/**|src/api/util.kt|overlaps
src/api/**|src/web/**|separate
src/api/**|src/**|overlaps
src/*.py|src/*.kt|overlaps
README.md|README.md|overlaps
README.md|docs/README.md|separate
docs/|docs/a.md|overlaps
src/a.py|src/b.py|separate
src|src/a.py|separate
**/test_*.py|src/api/test_x.py|overlaps
**/test_*.py|src/api/x.py|separate
TABELLE

# b) planned: #71 holds src/api/**, #72 wants src/api/util.kt → refused, #71 named, nothing written
sandbox_plannable 71 "src/api/**"; in_sprint 71
st product-owner 71 planned > /dev/null || fail b:71-planned
sandbox_plannable 72 "src/api/util.kt"; in_sprint 72
s1="$(sandbox_snap 72)"; ob="$(st product-owner 72 planned)"; s2="$(sandbox_snap 72)"
expect b-overlaps "$ob" '*rejected*#72 and #71*src/api/util.kt ~ src/api/*'
n=$((n + 1)); [ "$s1" = "$s2" ] || fail b:state-changed

# c) an approved ticket outside the sprint does not count
sandbox_issue 74 '{"comments":["**Planned** — product-owner · eval · session `e`\n\nOWNS Revision 1: `src/web/**`"]}'
sandbox_plannable 73 "src/web/**"; in_sprint 73
expect c-other-sprint "$(st product-owner 73 planned)" '*backlog → planned*'

# d) a sprint ticket without an approval (still backlog) does not count
sandbox_plannable 75 "src/api2/**"; in_sprint 75
sandbox_plannable 72 "src/api2/**"
expect d-without-approval "$(st product-owner 72 planned)" '*backlog → planned*'

# e) revise.sh: #73 wants to add src/api/client.kt → overlaps #71, no comment; separate passes
k0="$(comment_count 73)"
sandbox_plannable 73 "src/web/**, src/api/client.kt"
expect e-revise-overlaps "$(KIT_ROLE=product-owner "$BIN/revise.sh" 73 "src/web/**, src/api/client.kt" "Client gehoert dazu" 2>&1)" '*rejected*#73 and #71*src/api/client.kt*'
n=$((n + 1)); [ "$(comment_count 73)" = "$k0" ] || fail "e:comment-despite-the-rejection"
sandbox_plannable 73 "src/web/**, assets/**"
expect e-revise-separate "$(KIT_ROLE=product-owner "$BIN/revise.sh" 73 "src/web/**, assets/**" "Assets gehoeren dazu" 2>&1)" '*revision 1 → 2*'

# f) sprint-new.sh: #81 lib/**, #82 lib/x.py → refused, no sprint created; separate passes
sandbox_plannable 81 "lib/**"; sandbox_plannable 82 "lib/x.py"
dirs0="$(ls "$SANDBOX/sprints" | tr '\n' ' ')"; cur0="$(cat "$SANDBOX/sprints/CURRENT")"
expect f-sprint-overlaps "$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" zwei 81 82 2>&1)" '*rejected*#81 and #82*lib/x.py*'
n=$((n + 1)); [ "$(ls "$SANDBOX/sprints" | tr '\n' ' ')" = "$dirs0" ] && [ "$(cat "$SANDBOX/sprints/CURRENT")" = "$cur0" ] || fail f:sprint-created-anyway
sandbox_plannable 82 "tools/**"
expect f-sprint-separate "$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" zwei 81 82 2>&1)" '*S-002-zwei created*'

# g) the gh path: an overlap with #91; if the comments of #91 are not readable, that is a failure
fake_gh "$(python3 - <<'PY'
import json
freigabe = "**Planned** — product-owner · eval · session `e`\n\nOWNS Revision 1: `pkg/core/**`"
db = {
    "91": {"labels": ["sprint:current", "status:planned"], "assignees": [], "state": "OPEN", "comments": [freigabe], "board": "o-planned"},
    "92": {"labels": ["sprint:current"], "assignees": [], "state": "OPEN", "comments": [], "board": None, "body": "AC-1: the result is observable"},
}
print(json.dumps(db))
PY
)"
sandbox_ledger 92 <<'LEDGER'
# Gates: #92

OWNS: pkg/core/io.go

- [ ] AC-1: the result is observable
  CHECK: python3 tools/check_result.py
  EXPECT: result checked
  EVIDENCE: pending
LEDGER
expect g-gh-overlaps "$(st product-owner 92 planned)" '*rejected*#92 and #91*pkg/core/io.go*'
expect g-gh-comments-error "$(FAKE_GH_FAIL=comments st product-owner 92 planned)" '*#91: comments not readable*'

observe "$((n - wrong))/$n checks passed · 11 glob pairs · planned with a byte comparison, another sprint, without an approval · revise overlaps/separate · sprint-new overlaps without creating/separate · gh: an overlap, a comments error${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
