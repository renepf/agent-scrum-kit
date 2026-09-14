#!/usr/bin/env bash
CASE_DESC="restart-self.sh beendet nichts, solange Schleife, frische Uebergabe oder Ticketgrenze fehlen"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$OPFER" 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
sleep 300 & OPFER=$!
export KIT_ROLE=engineer-a KIT_HOST_PID="$OPFER"
rs() { "$BIN/restart-self.sh" "$@" 2>&1; }
fehler=""
o1="$(rs neugier)";                    case "$o1" in *"Anlass fehlt"*) ;; *) fehler="$fehler anlass" ;; esac
o2="$(rs stop)";                       case "$o2" in *"nicht unter"*) ;; *) fehler="$fehler schleife" ;; esac
export KIT_ROLE_LOOP=1
o3="$(rs stop)";                       case "$o3" in *"keine Uebergabe"*) ;; *) fehler="$fehler keine-uebergabe" ;; esac
"$BIN/brain.sh" handover "Stand 2026-09-14" <<<'Ticket #7 in rfr.' > /dev/null
H="$(ls "$SANDBOX/memory/engineer-a/handover/"*.md)"; touch -t "$(date -v-30M '+%Y%m%d%H%M' 2>/dev/null || date -d '-30 min' '+%Y%m%d%H%M')" "$H"
o4="$(rs stop)";                       case "$o4" in *"min alt"*) ;; *) fehler="$fehler alte-uebergabe" ;; esac
touch "$H"
sandbox_issue 7 '{"labels":["sprint:current","status:in-progress","owner:engineer-a"]}'
o5="$(rs stop)";                       case "$o5" in *"keine Ticketgrenze"*"#7"*) ;; *) fehler="$fehler ticketgrenze:'$o5'" ;; esac
kill -0 "$OPFER" 2>/dev/null || fehler="$fehler prozess-beendet-trotz-ablehnung"
sandbox_issue 7 '{"labels":["sprint:current","status:rfr"]}'
o6="$(KIT_RESTART_DRY_RUN=1 rs stop)"; case "$o6" in *"DRY-RUN"*"$OPFER"*) ;; *) fehler="$fehler alle-bedingungen-erfuellt:'$o6'" ;; esac
observe "Anlass/Schleife/Uebergabe/alt/Ticket gehalten → 5 Ablehnungen, Prozess lebt · alle Bedingungen → '$o6'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
