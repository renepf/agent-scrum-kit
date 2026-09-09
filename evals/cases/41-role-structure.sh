#!/usr/bin/env bash
CASE_DESC="jede Jobbeschreibung hat denselben Aufbau: alle sieben Abschnitte"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ABSCHNITTE="Auftrag|Besessener Status|Aufnahmebedingung|Arbeitsschritte|Abgabebedingung|Verdict-Format|Harte Grenzen"
fehlend=""
for f in "$KIT_ROOT"/roles/*.md; do
  b="$(basename "$f")"
  case "$b" in _COMMON.md|START-HERE.md) continue ;; esac
  for a in $(echo "$ABSCHNITTE" | tr '|' ' '); do :; done
  for a in "Auftrag" "Besessener Status" "Aufnahmebedingung" "Arbeitsschritte" "Abgabebedingung" "Verdict-Format" "Harte Grenzen"; do
    grep -q "^## $a" "$f" || fehlend="$fehlend $b:'$a'"
  done
done
anzahl="$(ls "$KIT_ROOT"/roles/*.md | grep -vcE '_COMMON|START-HERE')"

observe "$anzahl Rollen geprueft · fehlende Abschnitte:${fehlend:- keine}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehlend" ]
