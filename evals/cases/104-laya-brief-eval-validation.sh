#!/usr/bin/env bash
CASE_DESC="laya_brief_eval: bad cases file or --wiki fails before a server starts (exit 2), a failing wiki.py is not a miss, file match is by exact folder (and-my-auth__AuthVm.kt.md is not feature/auth/AuthVm.kt); fake laya, no model"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/brief-eval.XXXXXX")"
trap 'rm -rf "$T"' EXIT
n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 160)'" ;; esac; }

mkdir -p "$T/fake" "$T/src/feature/my-auth"
printf 'Q = {}\n' > "$T/q.py"
cat > "$T/fake/laya.py" <<'PY'
def load(*a, **k):
    class A:
        def predict(self, q, Q): return {"answers": {ax: {"choice": "auth", "probabilities": {"auth": 0.9}} for ax in ("feature", "kind", "side")}}
    return A()
PY
S="$T/src"; git -C "$S" init -q
printf '# Login\n\n## Intent\n\nlogin user\n' > "$S/feature/my-auth/intent.md"
printf 'package x\nclass AuthVm {\n    fun login(user: String) { }\n}\n' > "$S/feature/my-auth/AuthVm.kt"
git -C "$S" add . && git -C "$S" -c user.name=t -c user.email=t@t commit -qm init
SHA="$(git -C "$S" rev-parse --short HEAD)"
export WIKI_ROOT="$T/wiki" WIKI_STAGING="$T/staging" WIKI_REPOS="and=$S"
mkdir -p "$WIKI_ROOT"
cat > "$T/scope.json" <<J
{"feature":"auth","title":"Auth","readme":{"tag":"and","commit":"$SHA","path":"feature/my-auth/AuthVm.kt"},
 "sources":[{"tag":"and","commit":"$SHA","kind":"kotlin","globs":["feature/my-auth/*.kt"]},
            {"tag":"and","commit":"$SHA","kind":"md","globs":["feature/my-auth/*.md"]}]}
J
"$BIN/wiki.sh" scan "$T/scope.json" >/dev/null

EV() { PYTHONPATH="$T/fake" python3 "$BIN/laya_brief_eval.py" "$@" 2>&1; echo "rc=$?"; }
ok='{"id":"a","role":"dev","question":"login","expect_topic":"auth","expect_file":"feature/auth/AuthVm.kt"}'
case_json() { printf '[%s]' "$1" > "$T/c.json"; }

case_json '{"id":"a","role":"dev","question":"login","expect_topic":"auth"}'
expect missing-key "$(EV "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT")" '*case a: missing key expect_file*rc=2'
case_json '{"id":"b","role":"dev","question":"login","expect_topic":"auth","expect_file":"AuthVm.kt"}'
expect no-folder "$(EV "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT")" '*case b*folder*rc=2'
case_json '{"id":"c","role":"dev","question":"login","expect_topic":"auth","expect_file":"feature/auth/AuthVm.kt","expect_lines":[9,2]}'
expect reversed "$(EV "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT")" '*case c*expect_lines*rc=2'
case_json "$ok"
expect no-wiki "$(EV "$T/c.json" --questions "$T/q.py" --wiki "$T/nowhere")" '*--wiki is not a directory*rc=2'

printf '[%s,%s]' "$ok" '{"id":"d","role":"dev","question":"login","expect_topic":"auth","expect_file":"feature/my-auth/AuthVm.kt"}' > "$T/c.json"
out="$(EV "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT" --out "$T/r.json" --ft "$T/ft")"
hits="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["triage-ft"]; print([x["file_hit"] for x in r])' "$T/r.json" 2>&1)"
expect exact-folder "$hits" '\[False, True\]'
case_json '{"id":"e","role":"dev","question":"login","expect_topic":"auth","expect_file":"feature/my-auth/intent.md"}'
EV "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT" --out "$T/r3.json" --ft "$T/ft" >/dev/null
expect md-source "$(python3 -c 'import json,sys; print([x["file_hit"] for x in json.load(open(sys.argv[1]))["triage-ft"]])' "$T/r3.json" 2>&1)" '\[True\]'
env -u WIKI_LAYA_MODEL PYTHONPATH="$T/fake" python3 "$BIN/laya_brief_eval.py" "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT" --out "$T/r4.json" >/dev/null 2>&1
expect no-ft-no-row "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$T/r4.json" 2>&1)" "\['base-laya', 'lexical'\]"
printf '[]' > "$T/c.json"
expect no-cases "$(EV "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT")" '*no cases*rc=2'
case_json "$ok"; mkdir "$T/emptywiki"
expect empty-wiki "$(EV "$T/c.json" --questions "$T/q.py" --wiki "$T/emptywiki")" '*no concept files*rc=2'

# a wiki.py that exits non-zero must stop the run, not score as a miss
printf '#!/bin/sh\nexit 3\n' > "$T/wiki.py"; cp "$BIN/laya_brief_eval.py" "$T/laya_brief_eval.py"; cp "$BIN/wiki_route.py" "$T/"
out="$(PYTHONPATH="$T/fake" python3 "$T/laya_brief_eval.py" "$T/c.json" --questions "$T/q.py" --wiki "$WIKI_ROOT" --out "$T/r2.json" --ft "$T/ft" 2>&1; echo "rc=$?")"
expect wiki-fails "$out" '*wiki.py brief failed (exit*rc=1'

observe "$((n - failed))/$n checks passed · case file and --wiki validated before any server, exact folder match, failing wiki.py stops the run${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
