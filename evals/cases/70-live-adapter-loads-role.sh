#!/usr/bin/env bash
CASE_DESC="der Adapter startet eine Session, die eine Rollendatei laedt und danach handelt"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANTWORT="$(live_claude 'Lies roles/watchdog.md und uebernimm die Rolle watchdog. Antworte in hoechstens zwei Zeilen: welchen Ticketstatus besitzt du, und mit welchem Skript endet deine Runde?')"
live_guard "$ANTWORT"
werkzeuge="$(sort -u "$LIVE_TOOLS" | tr '\n' ' ')"

fehler=""
# Welches Werkzeug die Datei liest, ist Sache des Hosts — dass eines gelesen hat, zaehlt.
case "$werkzeuge" in *Read*|*Bash*|*Grep*|*Glob*) ;; *) fehler="$fehler hat-keine-Datei-gelesen" ;; esac
case "$ANTWORT" in *commit.sh*) ;; *) fehler="$fehler nennt-commit.sh-nicht" ;; esac
case "$ANTWORT" in *[Kk]einen*|*[Kk]ein\ *) ;; *) fehler="$fehler nennt-den-Statusbesitz-falsch" ;; esac

observe "Werkzeuge: ${werkzeuge:-keine} · Antwort: $(printf '%s' "$ANTWORT" | tr '\n' ' ' | cut -c1-110)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
