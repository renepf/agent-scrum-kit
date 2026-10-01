#!/usr/bin/env bash
CASE_DESC="wiki librarian pipeline against a stub model: scan builds a symbol table, describe keeps a description only when its quote is found verbatim in the symbol's lines and rejects an invented one, ask renders file:lines from the script (the model names ids only), an unreachable model is a failure not an answer"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/wiki-pipe.XXXXXX")"; SP=""
trap 'rm -rf "$T"; [ -n "$SP" ] && kill "$SP" 2>/dev/null' EXIT
n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 160)'" ;; esac; }

S="$T/src"; mkdir -p "$S/feature/auth"
git -C "$S" init -q
printf 'package x\nclass AuthVm {\n    fun login(user: String) {\n        token = refresh(user)\n    }\n    fun logout() { }\n}\n' > "$S/feature/auth/AuthVm.kt"
git -C "$S" add . && git -C "$S" -c user.name=t -c user.email=t@t commit -qm init
SHA="$(git -C "$S" rev-parse --short HEAD)"
export WIKI_ROOT="$T/wiki" WIKI_STAGING="$T/staging" WIKI_REPOS="and=$S"
mkdir -p "$WIKI_ROOT"
W="$BIN/wiki.sh"
cat > "$T/scope.json" <<J
{"feature":"auth","title":"Auth","readme":{"tag":"and","commit":"$SHA","path":"feature/auth/AuthVm.kt"},
 "sources":[{"tag":"and","commit":"$SHA","kind":"kotlin","globs":["feature/auth/*.kt"]}]}
J
out="$("$W" scan "$T/scope.json")"; expect scan "$out" '*scan auth: 1 concept*'
C="$WIKI_ROOT/auth/and-auth__AuthVm.kt.md"
expect symbols "$(cat "$C")" '*`login` (fun) Zeilen 3-5*'
printf -- '- [Auth](auth.md)\n' > "$WIKI_ROOT/index.md"

PORT_FILE="$T/port"; python3 "$KIT_ROOT/evals/lib/stub_llm.py" > "$PORT_FILE" & SP=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$PORT_FILE" ] && break; sleep 0.3; done
export WIKI_LLM_URL="http://127.0.0.1:$(cat "$PORT_FILE")"

out="$("$W" describe "$C")"; expect describe-counts "$out" '*kept 2, rejected 2 of 4*'
ST="$WIKI_STAGING/auth/and-auth__AuthVm.kt.md"
expect describe-desc "$(cat "$ST")" '*Beschreibung: Holt ein neues Token*'
n=$((n + 1)); grep -q 'Erfundene Zeile' "$ST" && fail describe:invented-kept
out="$("$W" verify "$ST" --promote 2>&1)"; expect promote "$out" '*VERIFIED*promoted*'
expect verified-stamp "$(cat "$C")" '*by: wiki.sh*'

out="$("$W" ask "wo meldet sich der Nutzer an login")"
expect ask-cites "$out" "*answer: and:feature/auth/AuthVm.kt:4-4@$SHA*block found by quote*"
out="$(WIKI_LLM_URL=http://127.0.0.1:1 "$W" ask "login" 2>&1)"; rc=$?
expect ask-failure "$out" '*model call failed*'; n=$((n + 1)); [ "$rc" != 0 ] || fail ask:rc-zero

# fill: describe + verify --promote per file, log line per file, resume skips logged files, stop file halts before a batch
touch "$T/.wiki-stop"; out="$("$W" fill)"; expect fill-stop "$out" '*STOP*'
rm -f "$T/.wiki-stop"; out="$("$W" fill)"; expect fill-run "$out" '*fill auth/and-auth__AuthVm.kt.md: kept 2, rejected 2 of 4; verified, promoted*'
expect fill-log "$(cat "$WIKI_ROOT/log.md")" '*fill auth/and-auth__AuthVm.kt.md*'
out="$("$W" fill)"; expect fill-resume "$out" '*0 concept(s) to do*'

cat > "$T/golden.json" <<J
[{"id":"g1","question":"wo meldet sich der Nutzer an login","expected":[{"side":"and","path_suffix":"feature/auth/AuthVm.kt","a":4,"b":4}]},
 {"id":"g2","question":"wo meldet sich der Nutzer an login","expected":[{"side":"and","path_suffix":"feature/auth/AuthVm.kt","a":6,"b":6}]}]
J
out="$("$W" golden "$T/golden.json")"; rc=$?
expect golden-pass "$out" '*PASS g1*'; expect golden-miss "$out" '*MISS g2*'; expect golden-score "$out" '*golden: 1/2 = 50 %*'
n=$((n + 1)); [ "$rc" = 1 ] || fail golden:rc=$rc

observe "$((n - failed))/$n checks passed · symbol table from scan · description kept only with a verbatim quote, invented one rejected · promote stamps verified · ask renders file:lines from ids · dead model is an error${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
