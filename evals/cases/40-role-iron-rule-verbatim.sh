#!/usr/bin/env bash
CASE_DESC="jede Jobbeschreibung traegt die eiserne Regel woertlich und byte-identisch"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

n=0; ohne=""; hashes=""
for f in "$KIT_ROOT"/roles/*.md; do
  case "$(basename "$f")" in START-HERE.md) continue ;; esac
  n=$((n + 1))
  block="$(grep -A4 '^## Eiserne Regel' "$f")"
  case "$block" in
    *"spawnt niemals einen Subagenten"*) hashes="$hashes$(printf '%s' "$block" | shasum | cut -d' ' -f1)
" ;;
    *) ohne="$ohne $(basename "$f")" ;;
  esac
done
verschieden="$(printf '%s' "$hashes" | sort -u | grep -c . )"

observe "$n Rollendateien · ohne Regel:${ohne:- keine} · verschiedene Fassungen des Blocks: $verschieden"
echo "BEOBACHTET: $OBSERVED"
[ -z "$ohne" ] && [ "$verschieden" = 1 ]
