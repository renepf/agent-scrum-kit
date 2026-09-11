#!/usr/bin/env bash
CASE_DESC="Gedaechtnisregeln: Dublette, relatives Datum und falscher Typ werden abgelehnt; gleicher Slug aendert"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
export KIT_ROLE=engineer-a
b() { "$BIN/brain.sh" "$@" 2>&1; }
fehler=""
b note api-limit "GitHub-API liefert kurz nach Schreiben veraltete Zaehlwerte" <<<'Gemessen 2026-09-10.' > /dev/null || fehler="$fehler erster-Fakt"
o1="$(b note api-limit-zwei "GitHub-API liefert kurz nach Schreiben veraltete  zaehlwerte" <<<'x')"
case "$o1" in *Dublette*api-limit.md*) ;; *) fehler="$fehler Dublette-durch" ;; esac
o2="$(b note wetter "Board war langsam" <<<'Das war gestern so.')"
case "$o2" in *"relative Datumsangabe 'gestern'"*) ;; *) fehler="$fehler relatives-Datum-durch" ;; esac
o3="$(TYPE=vermutung b note typ-test "Typ-Test" <<<'x')"
case "$o3" in *"Typ 'vermutung' ungueltig"*) ;; *) fehler="$fehler falscher-Typ-durch" ;; esac
o4="$(b note api-limit "GitHub-API liefert kurz nach Schreiben veraltete Zaehlwerte" <<<'Korrigiert 2026-09-11: auch Feldwerte betroffen.')" || fehler="$fehler gleicher-Slug-abgelehnt"
anzahl="$(ls "$SANDBOX/memory/engineer-a/facts" | wc -l | tr -d ' ')"
grep -q 'Korrigiert 2026-09-11' "$SANDBOX/memory/engineer-a/facts/api-limit.md" || fehler="$fehler Aenderung-nicht-geschrieben"
[ "$anzahl" = 1 ] || fehler="$fehler $anzahl-Dateien-statt-1"
observe "Dublette (andere Schreibweise) → abgelehnt · 'gestern' → abgelehnt · Typ 'vermutung' → abgelehnt · gleicher Slug → geaendert, $anzahl Datei${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
