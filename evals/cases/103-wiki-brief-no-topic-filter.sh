#!/usr/bin/env bash
CASE_DESC="wiki brief: a Laya route of feature other, or a topic with no folder in the wiki, applies no topic filter (lexical over the whole wiki, also with side none); a known topic still filters"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/wiki-brief.XXXXXX")"; SP=""
trap 'rm -rf "$T"; [ -n "$SP" ] && kill "$SP" 2>/dev/null' EXIT
n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 160)'" ;; esac; }

S="$T/src"; mkdir -p "$S/feature/auth"
git -C "$S" init -q
printf 'package x\nclass AuthVm {\n    fun login(user: String) { }\n}\n' > "$S/feature/auth/AuthVm.kt"
git -C "$S" add . && git -C "$S" -c user.name=t -c user.email=t@t commit -qm init
SHA="$(git -C "$S" rev-parse --short HEAD)"
export WIKI_ROOT="$T/wiki" WIKI_STAGING="$T/staging" WIKI_REPOS="and=$S"
mkdir -p "$WIKI_ROOT"
W="$BIN/wiki.sh"
cat > "$T/scope.json" <<J
{"feature":"auth","title":"Auth","readme":{"tag":"and","commit":"$SHA","path":"feature/auth/AuthVm.kt"},
 "sources":[{"tag":"and","commit":"$SHA","kind":"kotlin","globs":["feature/auth/*.kt"]}]}
J
"$W" scan "$T/scope.json" >/dev/null

PORT_FILE="$T/port"; python3 "$KIT_ROOT/evals/lib/stub_llm.py" > "$PORT_FILE" & SP=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$PORT_FILE" ] && break; sleep 0.3; done
export WIKI_ROUTE_URL="http://127.0.0.1:$(cat "$PORT_FILE")"

out="$("$W" brief "login OTHERTOPIC")"; expect other "$out" '*topic: other*auth/and-auth__AuthVm.kt.md*'
out="$("$W" brief "login GHOSTTOPIC")"; expect ghost "$out" '*topic: ghost*platform none*auth/and-auth__AuthVm.kt.md*'
out="$("$W" brief "login")"; expect known "$out" '*topic: auth*auth/and-auth__AuthVm.kt.md*'

observe "$((n - failed))/$n checks passed · route other or unknown topic = no topic filter, side none does not filter, known topic still filters${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
