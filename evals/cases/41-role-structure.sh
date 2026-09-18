#!/usr/bin/env bash
CASE_DESC="every job description has the same structure: all seven sections"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

SECTIONS="Auftrag|Besessener Status|Aufnahmebedingung|Arbeitsschritte|Abgabebedingung|Verdict-Format|Harte Grenzen"
missing=""
for f in "$KIT_ROOT"/roles/*.md; do
  b="$(basename "$f")"
  case "$b" in _COMMON.md|START-HERE.md) continue ;; esac
  for a in $(echo "$SECTIONS" | tr '|' ' '); do :; done
  for a in "Mission" "Owned status" "Pick-up condition" "Working steps" "Hand-off condition" "Verdict format" "Hard limits"; do
    grep -q "^## $a" "$f" || missing="$missing $b:'$a'"
  done
done
count="$(ls "$KIT_ROOT"/roles/*.md | grep -vcE '_COMMON|START-HERE')"

observe "$count roles checked · missing sections:${missing:- none}"
echo "OBSERVED: $OBSERVED"
[ -z "$missing" ]
