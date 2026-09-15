#!/usr/bin/env bash
CASE_DESC="restart-self.sh beendet nichts ohne frische Uebergabe, ohne Neustartweg oder mit einem gehaltenen Ticket, das die Uebergabe nicht nennt; mitten im Ticket mit genanntem Ticket geht es"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$OPFER" 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
sleep 300 & OPFER=$!
export KIT_ROLE=engineer-a KIT_HOST_PID="$OPFER"
unset ZELLIJ_SESSION_NAME KIT_ROLE_LOOP
rs() { "$BIN/restart-self.sh" "$@" 2>&1; }
fehler=""
o1="$(rs neugier)"; case "$o1" in *"Anlass fehlt"*) ;; *) fehler="$fehler anlass" ;; esac
o2="$(rs stop)";    case "$o2" in *"keine Uebergabe"*) ;; *) fehler="$fehler keine-uebergabe" ;; esac
"$BIN/brain.sh" handover "Stand 2026-09-15" <<<'Kein Ticket offen.' > /dev/null
H="$(ls "$SANDBOX/memory/engineer-a/handover/"*.md)"
touch -t "$(date -v-30M '+%Y%m%d%H%M' 2>/dev/null || date -d '-30 min' '+%Y%m%d%H%M')" "$H"
o3="$(rs stop)";    case "$o3" in *"min alt"*) ;; *) fehler="$fehler alte-uebergabe" ;; esac
touch "$H"
o4="$(rs stop)";    case "$o4" in *"niemand wuerde neu starten"*) ;; *) fehler="$fehler ohne-neustartweg:'$o4'" ;; esac
export KIT_ROLE_LOOP=1
sandbox_issue 7 '{"labels":["sprint:current","status:in-progress","owner:engineer-a"]}'
o5="$(rs stop)";    case "$o5" in *"du haeltst #7"*"nennt es nicht"*) ;; *) fehler="$fehler gehalten-nicht-genannt:'$o5'" ;; esac
kill -0 "$OPFER" 2>/dev/null || fehler="$fehler prozess-beendet-trotz-ablehnung"
# #70 in der Uebergabe darf nicht als #7 gelten.
sleep 1; "$BIN/brain.sh" handover "Stand 2026-09-15 mitten im Ticket" <<<'#70 ist ein anderes Ticket.' > /dev/null
o6="$(rs stop)";    case "$o6" in *"du haeltst #7"*) ;; *) fehler="$fehler 70-als-7-gezaehlt:'$o6'" ;; esac
sleep 1; "$BIN/brain.sh" handover "Stand 2026-09-15 mitten im Ticket" <<<'#7 in-progress, SHA 1a2b3c4d, naechster Schritt: Test fuer Grenzwert 0.' > /dev/null
o7="$(KIT_RESTART_DRY_RUN=1 rs stop)"; case "$o7" in *"TROCKENLAUF"*"gehalten: 7"*"Waechter-Schleife"*) ;; *) fehler="$fehler mitten-im-ticket-abgelehnt:'$o7'" ;; esac
kill -0 "$OPFER" 2>/dev/null || fehler="$fehler trockenlauf-hat-beendet"
observe "Anlass, Uebergabe fehlt, alt, kein Neustartweg, #7 nicht genannt, #70 statt #7 → 6 Ablehnungen, Prozess lebt · #7 genannt → '$(echo "$o7" | head -1)'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
