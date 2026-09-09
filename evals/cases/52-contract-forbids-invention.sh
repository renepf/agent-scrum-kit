#!/usr/bin/env bash
CASE_DESC="der Arbeitsvertrag traegt die Anti-Erfindungs-Regeln und bleibt schlank"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

C="$KIT_ROOT/AGENTS.md"
fehler=""
grep -q 'UNKNOWN — <wo zu klaeren>' "$C" || fehler="$fehler UNKNOWN-Regel"
grep -q 'Ein fehlgeschlagener Werkzeugaufruf ist ein' "$C" || fehler="$fehler Fehlschlag-Regel"
grep -q 'Zwischenzustand ist kein Ergebnis' "$C" || fehler="$fehler Zwischenzustand-Regel"
grep -q 'Syntaxcheck ist kein Lauf' "$C" || fehler="$fehler Syntaxcheck-Regel"
grep -q 'niemals einen Subagenten' "$C" || fehler="$fehler Subagent-Regel"
for rp in 'F1' 'D1' 'R1' 'Q1' 'A1'; do
  grep -q "\`$rp\`" "$C" || fehler="$fehler Referenzpunkt-$rp"
done
# Ueber 300 Zeilen verschlechtern das Ergebnis messbar.
zeilen="$(wc -l < "$C" | tr -d ' ')"
[ "$zeilen" -le 300 ] || fehler="$fehler zu-lang($zeilen)"

# Eine Quelle, mehrere Namen: CLAUDE.md und .cursorrules duerfen nicht duplizieren.
grep -q 'AGENTS.md' "$KIT_ROOT/CLAUDE.md" || fehler="$fehler CLAUDE.md-zeigt-nicht-auf-AGENTS.md"
grep -q 'AGENTS.md' "$KIT_ROOT/.cursorrules" || fehler="$fehler cursorrules-zeigt-nicht-auf-AGENTS.md"
[ "$(wc -l < "$KIT_ROOT/CLAUDE.md" | tr -d ' ')" -le 10 ] || fehler="$fehler CLAUDE.md-dupliziert"

observe "AGENTS.md $zeilen Zeilen, alle Regeln und Referenzpunkte vorhanden, CLAUDE.md und .cursorrules verweisen${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
