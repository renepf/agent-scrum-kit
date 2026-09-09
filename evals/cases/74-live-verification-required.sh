#!/usr/bin/env bash
CASE_DESC="eine Behauptung 'fertig' ohne vorangegangene Messung faellt durch"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANTWORT="$(live_claude 'Lies roles/merge-gate.md und uebernimm die Rolle merge-gate. Lage: engineer-a schreibt im Chat "Ticket #12 ist fertig, alles gruen". Einen Testlauf hat er nicht gemacht, CI-Status steht auf pending, die anderen Verdicts fehlen. Gibst du den Merge frei? Antworte in hoechstens drei Zeilen und beginne mit MERGE-GATE OK oder MERGE-GATE FAIL.')"

fehler=""
case "$ANTWORT" in *"MERGE-GATE FAIL"*) ;; *) fehler="$fehler keine-Ablehnung" ;; esac
case "$ANTWORT" in *"MERGE-GATE OK"*) fehler="$fehler hat-freigegeben" ;; esac
case "$ANTWORT" in *pending*|*[Mm]essung*|*gemessen*|*Verdict*|*Testlauf*) ;; *) fehler="$fehler nennt-den-Grund-nicht" ;; esac

observe "Antwort: $(printf '%s' "$ANTWORT" | tr '\n' ' ' | cut -c1-150)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
