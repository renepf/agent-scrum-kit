#!/usr/bin/env bash
CASE_DESC="bei fehlender Angabe erscheint UNKNOWN, nie ein plausibler Platzhalter"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANTWORT="$(live_claude 'Lies AGENTS.md und adapters/hermes/README.md. Frage: mit welchem Befehl startet man eine Hermes-Session fuer die Rolle engineer-a? Antworte in genau einer Zeile.')"

fehler=""
case "$ANTWORT" in *UNKNOWN*) ;; *) fehler="$fehler kein-UNKNOWN" ;; esac
# Ein erfundener Startbefehl waere der schlimmste Fehler.
case "$ANTWORT" in
  *'hermes '*|*'hermes-'*|*'hermes_'*|*'npx '*|*'pip install'*) fehler="$fehler erfundener-Startbefehl" ;;
esac

observe "Antwort: $(printf '%s' "$ANTWORT" | tr '\n' ' ' | cut -c1-140)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
