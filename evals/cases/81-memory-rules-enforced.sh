#!/usr/bin/env bash
CASE_DESC="memory rules: a duplicate, a relative date and a wrong type are refused; the same slug changes it"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
export KIT_ROLE=engineer-a
b() { "$BIN/brain.sh" "$@" 2>&1; }
errors=""
b note api-limit "the GitHub API returns stale counts shortly after a write" <<<'Measured 2026-09-10.' > /dev/null || errors="$errors first-fact"
o1="$(b note api-limit-zwei "the GitHub API returns stale  counts shortly after a write" <<<'x')"
case "$o1" in *duplicate*api-limit.md*) ;; *) errors="$errors duplicate-let-through" ;; esac
o2="$(b note wetter "the board was slow" <<<'That was the case gestern.')"
case "$o2" in *"relative date 'gestern'"*) ;; *) errors="$errors relative-date-let-through" ;; esac
o3="$(TYPE=vermutung b note typ-test "type test" <<<'x')"
case "$o3" in *"type 'vermutung' invalid"*) ;; *) errors="$errors wrong-type-let-through" ;; esac
o4="$(b note api-limit "the GitHub API returns stale counts shortly after a write" <<<'Corrected 2026-09-11: field values are affected too.')" || errors="$errors same-slug-refused"
count="$(ls "$SANDBOX/memory/engineer-a/facts" | wc -l | tr -d ' ')"
grep -q 'Corrected 2026-09-11' "$SANDBOX/memory/engineer-a/facts/api-limit.md" || errors="$errors change-not-written"
[ "$count" = 1 ] || errors="$errors $count-files-instead-of-1"
observe "a duplicate (spelled differently) → refused · 'gestern' → refused · type 'vermutung' → refused · the same slug → changed, $count file${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
