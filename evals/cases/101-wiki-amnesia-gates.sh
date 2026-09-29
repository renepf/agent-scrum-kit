#!/usr/bin/env bash
CASE_DESC="wiki amnesia gates: S1 seed is JSON and byte-identical, S2 denies an edit under a guarded path until a wiki query ran (the denial names the query command), S3 writes the receipt only for a wiki.sh query, an unguarded path and a session without a wiki stay silent"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/wiki-gate.XXXXXX")"; trap 'rm -rf "$T"' EXIT
n=0; failed=0; errors=""
fail() { failed=$((failed + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
H="$KIT_ROOT/adapters/claude-code/wiki-hook.sh"
export WIKI_ROOT="$T/wiki" WIKI_RECEIPT_DIR="$T/r" WIKI_GATE_PATHS="$T/src"
mkdir -p "$WIKI_ROOT" "$T/src"
printf -- '---\ntype: feature\ntitle: Login\nverified: []\n---\nlogin\n' > "$WIKI_ROOT/login.md"
edit() { printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" "$2"; }

a="$(: | "$H" seed)"; b="$(: | "$H" seed)"
n=$((n + 1)); [ "$a" = "$b" ] || fail s1:not-identical
expect s1-json "$a" '*"additionalContext"*wiki.sh query*'

out="$(edit s1 "$T/src/A.kt" | "$H" gate 2>&1)"; rc=$?
expect s2-denied "$out" '*wiki.sh query*'; n=$((n + 1)); [ "$rc" = 2 ] || fail s2:rc=$rc
edit s1 "$T/other/B.kt" | "$H" gate > /dev/null 2>&1; rc=$?; n=$((n + 1)); [ "$rc" = 0 ] || fail s2:unguarded-denied

printf '{"session_id":"s1","tool_input":{"command":"ls -la"}}' | "$H" receipt
edit s1 "$T/src/A.kt" | "$H" gate > /dev/null 2>&1; rc=$?; n=$((n + 1)); [ "$rc" = 2 ] || fail s3:receipt-from-ls
printf '{"session_id":"s1","tool_input":{"command":"bin/wiki.sh query \\"login\\""}}' | "$H" receipt
edit s1 "$T/src/A.kt" | "$H" gate > /dev/null 2>&1; rc=$?; n=$((n + 1)); [ "$rc" = 0 ] || fail s3:no-receipt-after-query
edit s2 "$T/src/A.kt" | "$H" gate > /dev/null 2>&1; rc=$?; n=$((n + 1)); [ "$rc" = 2 ] || fail s3:receipt-leaks-to-other-session

out="$(WIKI_ROOT= edit s9 "$T/src/A.kt" | WIKI_ROOT= "$H" gate 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] && [ -z "$out" ] || fail nowiki:rc=$rc

observe "$((n - failed))/$n checks passed · seed JSON identical · edit denied until query, denial names the command · receipt only from a wiki.sh query and only for its session · no wiki no output${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
