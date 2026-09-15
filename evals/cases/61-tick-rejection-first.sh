#!/usr/bin/env bash
CASE_DESC="tick zeigt einem Engineer die Rueckweisung vor jedem neuen Ticket, einem anderen Engineer nicht"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 21 '{"title":"zurueckgewiesenes Ticket","labels":["sprint:current"],"pr":{"number":210,"head":"abcabcabc1","comments":[]}}'
sandbox_plannable 21
sandbox_issue 22 '{"title":"neues Ticket","labels":["sprint:current","status:planned"]}'
KIT_ROLE=product-owner "$BIN/status.sh" 21 planned x > /dev/null
KIT_ROLE=engineer-a "$BIN/status.sh" 21 in-progress x > /dev/null
KIT_ROLE=engineer-a "$BIN/status.sh" 21 rfr x > /dev/null
KIT_ROLE=qa-ruthless "$BIN/status.sh" 21 in-review x > /dev/null
KIT_ROLE=qa-ruthless "$BIN/status.sh" 21 in-progress "Grenzwert 0 ungetestet" > /dev/null

a="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
b="$(KIT_ROLE=engineer-b "$BIN/tick.sh" 2>&1)"
pos_rueck="$(printf '%s\n' "$a" | grep -n 'ZURUECKGEWIESEN' | head -1 | cut -d: -f1)"
pos_neu="$(printf '%s\n' "$a" | grep -n '#22 ' | head -1 | cut -d: -f1)"

fehler=""
[ -n "$pos_rueck" ] || fehler="$fehler keine-Rueckweisung-fuer-engineer-a"
[ -n "$pos_neu" ] || fehler="$fehler neues-Ticket-fehlt"
[ -n "$pos_rueck" ] && [ -n "$pos_neu" ] && [ "$pos_rueck" -lt "$pos_neu" ] || fehler="$fehler Reihenfolge"
printf '%s' "$a" | grep -q 'Grenzwert 0 ungetestet' || fehler="$fehler Befund-nicht-gezeigt"
printf '%s' "$b" | grep -q 'ZURUECKGEWIESEN' && fehler="$fehler engineer-b-sieht-fremde-Rueckweisung"

observe "engineer-a: Rueckweisung Zeile $pos_rueck, neues Ticket Zeile $pos_neu · engineer-b sieht keine fremde Rueckweisung: $(printf '%s' "$b" | grep -q ZURUECK && echo NEIN || echo ja)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
