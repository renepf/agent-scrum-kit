#!/usr/bin/env bash
CASE_DESC="rfr only when every file of the PR, the old path of a rename included, lies within the OWNS revision the product-owner approved on the issue; revision, globs, the gh path"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 120)'" ;; esac; }
st() { KIT_ROLE="$1" "$BIN/status.sh" "$2" "$3" x 2>&1; }
rv() { KIT_ROLE="$1" "$BIN/revise.sh" 41 "$2" "$3" 2>&1; }
revision() { KIT_ROLE=product-owner "$BIN/tickets.sh" comments 41 | python3 "$BIN/gates.py" approved 2>/dev/null | cut -f1; }
comment_count() { KIT_ROLE=product-owner "$BIN/tickets.sh" comments 41 | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
unchanged() { # name nr befehl...
  local name="$1" nr="$2" s1 s2; shift 2
  s1="$(sandbox_snap "$nr")"; "$@" > /dev/null 2>&1; s2="$(sandbox_snap "$nr")"
  n=$((n + 1)); [ "$s1" = "$s2" ] || fail "$name:state-changed"
}

# a) A ledger without OWNS: planned refuses
sandbox_issue 42 '{"body":"AC-1: the result is measurable"}'
printf '# Gates: #42\n\n- [ ] AC-1: the result is measurable\n  CHECK: python3 tools/check.py\n  EXPECT: measured\n  EVIDENCE: pending\n' | sandbox_ledger 42
expect a-without-OWNS "$(st product-owner 42 planned)" '*without OWNS*'

# b) planned records OWNS as revision 1 in its own issue comment
sandbox_issue 41 '{"pr":{"number":410,"head":"41414141aa","comments":[],"files":["src/export/writer.py","tests/export/test_writer.py","README.md"]}}'
sandbox_plannable 41 "src/export/**, tests/export/**"
st product-owner 41 planned > /dev/null || fail b:planned
n=$((n + 1)); [ "$(revision)" = 1 ] || fail "b:revision='$(revision)'"
st engineer-a 41 in-progress > /dev/null || fail b:in-progress

# c) README.md outside: nothing written (already on the first attempt), refused, exactly that file named
unchanged c-writes-nothing 41 st engineer-a 41 rfr
oc="$(st engineer-a 41 rfr)"
expect c-outside "$oc" '*outside OWNS*README.md*'
case "$oc" in *writer.py*) fail c:file-inside-OWNS-named ;; esac

# d) The engineer extends OWNS in the ledger itself: does not count
sandbox_plannable 41 "src/export/**, tests/export/**, README.md"
expect d-self-extension "$(st engineer-a 41 rfr)" '*README.md*revise.sh*'

# d2) The engineer writes an approval line into a comment of their own: does not count
KIT_ROLE=engineer-a "$BIN/tickets.sh" comment 41 "**Notiz** — engineer-a · jetzt · session \`x\`

OWNS Revision 9: \`src/**, tests/**, README.md\`"
expect d2-foreign-approval-line "$(st engineer-a 41 rfr)" '*revision 1*outside OWNS*README.md*'

# e) The revision is refused: the wrong role, the call unequal to the ledger, the whole root, ** inside a segment,
#    only reordered, an absolute path. No rejection writes a comment.
k0="$(comment_count)"
expect e1-role "$(rv engineer-a "src/export/**, tests/export/**, README.md" "README needed")" '*only by the product-owner*'
expect e2-unequal-to-the-ledger "$(rv product-owner "src/**" "different from the ledger")" '*the ledger names*'
# The ledger check itself must refuse ("rejected — line ..."), not only the comparison with the call,
# which would quote its error message as "the ledger names '...'".
sandbox_plannable 41 "**"
expect e3-root "$(rv product-owner "**" "everything")" '*rejected — line*whole root*'
sandbox_plannable 41 "src**"
expect e4-segment "$(rv product-owner "src**" "segment")" '*rejected — line*whole path segment*'
sandbox_plannable 41 "tests/export/**, src/export/**"
expect e5-unchanged "$(rv product-owner "tests/export/**,src/export/**" "only reordered")" '*no new revision*'
sandbox_plannable 41 "/etc/**"
expect e6-absolute "$(rv product-owner "/etc/**" "absolute")" '*rejected — line*must be relative*'
sandbox_plannable 41 "src/export/**, tests/export/**, README.md"
sandbox_issue 41 '{"body":"AC-1: the export writes a file\nAC-2: the README names the export"}'
expect e7-AC-without-gate "$(rv product-owner "src/export/**, tests/export/**, README.md" "AC-2 missing in the ledger")" '*rejected — AC without a gate*AC-2*'
n=$((n + 1)); [ "$(comment_count)" = "$k0" ] || fail "e:comment-despite-rejection(${k0}->$(comment_count))"
n=$((n + 1)); [ "$(revision)" = 1 ] || fail "e:revision='$(revision)'"

# f) The product-owner approves the README: revision 2 names the old scope, the new scope and the reason
sandbox_plannable 41 "src/export/**, tests/export/**, README.md"
rv product-owner "README.md, src/export/**, tests/export/**" "AC-1 requires the hint in the README" > /dev/null || fail f:revise
n=$((n + 1)); [ "$(revision)" = 2 ] || fail "f:revision='$(revision)'"
kf="$(KIT_ROLE=product-owner "$BIN/tickets.sh" comments 41 | python3 -c 'import json,sys; print(" ".join(c for c in json.load(sys.stdin) if c.startswith("**OWNS Revision 2**")))')"
expect f-comment "$kf" '*revision 1*src/export/*OWNS Revision 2:*README.md*AC-1 requires the hint*'

# g) Gegenprobe: jetzt geht rfr durch
expect g-rfr "$(st engineer-a 41 rfr)" '*in-progress → rfr*'

# h) Without a linked PR there is no hand-off
sandbox_plannable 43
st product-owner 43 planned > /dev/null; st engineer-b 43 in-progress > /dev/null
expect h-without-PR "$(st engineer-b 43 rfr)" '*no linked PR*'

# i) Globs: one hit and one miss per form; an empty file list is a failure
while IFS='|' read -r g f soll; do
  [ -n "$g" ] || continue
  n=$((n + 1))
  printf '%s\n' "$f" | python3 "$BIN/gates.py" scope "$g" > /dev/null 2>&1 && ist=drin || ist=draussen
  [ "$ist" = "$soll" ] || fail "i:'$g'~'$f'=$ist"
done <<'TABELLE'
src/**|src/a.py|drin
src/**|src/x/y.py|drin
src/**|srcevil/a.py|draussen
src/*.py|src/a.py|drin
src/*.py|src/x/a.py|draussen
**/test_*.py|test_a.py|drin
**/test_*.py|a/b/test_a.py|drin
**/test_*.py|a/b/a.py|draussen
docs/|docs/a/b.md|drin
docs/|docsx/a.md|draussen
README.md|README.md|drin
README.md|x/README.md|draussen
a?.md|ab.md|drin
a?.md|a/.md|draussen
TABELLE
expect i-empty-list "$(printf '' | python3 "$BIN/gates.py" scope "src/**" 2>&1)" '*is empty*'

# j) unzulaessiges OWNS lehnt planned ab
for bad in "**" "./**" "*" "**/*" "src**" "/etc/**" "../x/**"; do
  n=$((n + 1))
  printf '# Gates\n\nOWNS: %s\n\n- [ ] AC-1: x\n  CHECK: python3 tools/check_x.py\n  EXPECT: x measured\n  EVIDENCE: pending\n' "$bad" > "$SANDBOX/bad.md"
  printf 'AC-1: x\n' | python3 "$BIN/gates.py" planned "$SANDBOX/bad.md" > /dev/null 2>&1 && fail "j:'$bad'-durch"
done

# k) The gh path (a faked gh): a rename, two PRs, a file-list error, a counter-check
fake_gh "$(python3 - <<'PY'
import json
freigabe = "**Planned** — product-owner · eval · session `e`\n\neval\n\nOWNS Revision 1: `src/**`"
def ticket(prs):
    return {"labels": ["status:in-progress", "owner:engineer-a"], "assignees": [], "state": "OPEN",
            "comments": [freigabe], "board": "o-inprogress", "prs": prs}
db = {"60": ticket(["600"]), "61": ticket(["610", "611"]), "62": ticket(["620"]), "63": ticket(["630"])}
db["pulls"] = {
    "600": {"head": "60606060aa", "files": [{"filename": "src/billing.py", "previous_filename": "legacy/billing.py"}]},
    "610": {"head": "61616161aa", "files": [{"filename": "src/a.py"}]},
    "611": {"head": "61616161bb", "files": [{"filename": "infra/deploy.yml"}]},
    "620": {"head": "62626262aa", "files": [{"filename": "src/a.py"}]},
    "630": {"head": "63636363aa", "files": [{"filename": "src/b.py", "previous_filename": "src/a.py"}]},
}
print(json.dumps(db))
PY
)"
expect k-rename "$(st engineer-a 60 rfr)" '*outside OWNS*legacy/billing.py*'
expect k-two-PRs "$(st engineer-a 61 rfr)" '*several linked PRs*'
expect k-file-list-error "$(FAKE_GH_FAIL=pr-files st engineer-a 62 rfr)" '*file list not readable*'
expect k-counter-check "$(st engineer-a 63 rfr)" '*in-progress → rfr*'

observe "$((n - wrong))/$n checks passed · file backend: OWNS mandatory, revision 1 on the issue, outside, self extension, a foreign approval line, 7 refused revisions, revision 2, rfr, without a PR · 14 globs + an empty list · 7 invalid OWNS · gh: a rename, two PRs, a file-list error, a counter-check${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
