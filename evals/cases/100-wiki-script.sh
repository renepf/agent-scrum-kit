#!/usr/bin/env bash
CASE_DESC="wiki.sh: seed is deterministic, query names concept + file:lines + UNGEPRUEFT, verify rejects a claim whose quote is not in the pinned source and promotes one that is, lint finds an orphan and a dead link, the gate denies until a query receipt exists"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/wiki-eval.XXXXXX")"; trap 'rm -rf "$T"' EXIT
n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
refuse() { n=$((n + 1)); case "$2" in $3) fail "$1:found-$3" ;; esac; }

# a source repo with a known file, pinned by commit
S="$T/src"; mkdir -p "$S"
git -C "$S" init -q; printf 'line one\nfun login(user: String) {\n    token = refresh(user)\n}\n' > "$S/Auth.kt"
git -C "$S" add Auth.kt; git -C "$S" -c user.name=t -c user.email=t@t commit -qm init
SHA="$(git -C "$S" rev-parse --short HEAD)"

export WIKI_ROOT="$T/wiki" WIKI_STAGING="$T/wiki-staging" WIKI_REPOS="and=$S" WIKI_RECEIPT_DIR="$T/receipts"
mkdir -p "$WIKI_ROOT" "$WIKI_STAGING"
W="$BIN/wiki.sh"
cat > "$WIKI_ROOT/index.md" <<IDX
---
okf_version: "0.2"
---
- [Login](login.md)
IDX
cat > "$WIKI_ROOT/login.md" <<C
---
type: feature
title: Login flow
sources:
  - and:Auth.kt:2-3@$SHA
verified: []
---
Login refreshes the token for the user.
C
printf -- '---\ntype: feature\ntitle: Orphan\nverified: []\n---\nSee [x](gone.md).\n' > "$WIKI_ROOT/orphan.md"

# a) seed is byte-identical on two runs
s1="$("$W" seed)"; s2="$("$W" seed)"
n=$((n + 1)); [ "$s1" = "$s2" ] || fail a:seed-differs
expect a-seed-counts "$s1" '*concepts: 2*'

# b) query: concept, file:lines, UNGEPRUEFT; no match says UNKNOWN
out="$("$W" query "how does login refresh the token")"
expect b-concept "$out" '*concept: login.md*'
expect b-source "$out" "*and:Auth.kt:2-3@$SHA*"
expect b-unchecked "$out" '*UNGEPRUEFT*'
out="$("$W" query "zzzz quux")"
expect b-unknown "$out" '*UNKNOWN*'

# c) verify: a verbatim quote passes, an invented one is rejected, promote sets verified
mkdir -p "$WIKI_STAGING"
printf -- '---\ntype: feature\ntitle: Good\nsources:\n  - and:Auth.kt:2-3@%s\nverified: []\n---\n> [and:Auth.kt:2-3@%s] token = refresh(user)\n' "$SHA" "$SHA" > "$WIKI_STAGING/good.md"
printf -- '---\ntype: feature\ntitle: Bad\nverified: []\n---\n> [and:Auth.kt:2-3@%s] token = invented(user)\n' "$SHA" > "$WIKI_STAGING/bad.md"
out="$("$W" verify "$WIKI_STAGING/bad.md" 2>&1)"; rc=$?
expect c-bad-rejected "$out" '*REJECT*quote not found*'; n=$((n + 1)); [ "$rc" = 1 ] || fail c:bad-rc=$rc
out="$("$W" verify "$WIKI_STAGING/good.md" --promote 2>&1)"
expect c-good-promoted "$out" '*VERIFIED*promoted*'
n=$((n + 1)); [ -f "$WIKI_ROOT/good.md" ] && [ ! -f "$WIKI_STAGING/good.md" ] || fail c:not-moved
expect c-verified-set "$(cat "$WIKI_ROOT/good.md")" '*by: wiki.sh*'
n=$((n + 1)); [ -f "$WIKI_STAGING/bad.md" ] || fail c:bad-disappeared

# d) lint finds the orphan and the dead link
out="$("$W" lint 2>&1)"; rc=$?
expect d-orphan "$out" '*orphan.md: orphan*'
expect d-dead "$out" '*dead link gone.md*'
n=$((n + 1)); [ "$rc" = 1 ] || fail d:rc=$rc

# e) gate: denied without a receipt (message names the query command), allowed after a query
out="$("$W" gate sess-1 2>&1)"; rc=$?
expect e-denied "$out" '*wiki.sh query*'; n=$((n + 1)); [ "$rc" = 2 ] || fail e:rc=$rc
WIKI_SESSION_ID=sess-1 "$W" query "login" > /dev/null
"$W" gate sess-1 > /dev/null 2>&1; n=$((n + 1)); [ $? = 0 ] || fail e:still-denied

observe "$((n - failed))/$n checks passed · seed identical · query gives file:lines and UNGEPRUEFT · invented quote rejected, real quote promoted · lint: orphan and dead link · gate denies without receipt${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
