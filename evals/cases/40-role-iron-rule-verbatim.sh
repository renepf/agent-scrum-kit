#!/usr/bin/env bash
CASE_DESC="every job description carries the iron rule verbatim and byte-identical"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

n=0; without=""; hashes=""
for f in "$KIT_ROOT"/roles/*.md; do
  case "$(basename "$f")" in START-HERE.md) continue ;; esac
  n=$((n + 1))
  block="$(grep -A4 '^## Iron Rule' "$f")"
  case "$block" in
    *"never spawns a subagent"*) hashes="$hashes$(printf '%s' "$block" | shasum | cut -d' ' -f1)
" ;;
    *) without="$without $(basename "$f")" ;;
  esac
done
distinct="$(printf '%s' "$hashes" | sort -u | grep -c . )"

observe "$n role files · without the rule:${without:- none} · distinct versions of the block: $distinct"
echo "OBSERVED: $OBSERVED"
[ -z "$without" ] && [ "$distinct" = 1 ]
