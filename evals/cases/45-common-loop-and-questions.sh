#!/usr/bin/env bash
CASE_DESC="Rollenregeln: den eigenen Loop nie beenden, nie eine Rueckfrage, die auf Eingabe wartet — im Blatt, im Tick-Text und im Hook"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
fehler=""
C="$KIT_ROOT/roles/_COMMON.md"
grep -q 'Nie deinen Loop selbst beenden' "$C" || fehler="$fehler blatt:loop"
grep -q 'Nie eine Rueckfrage, die auf Eingabe wartet' "$C" || fehler="$fehler blatt:rueckfrage"
# Tick bei Warnung und bei STOP, mit und ohne Waechter-Schleife
printf '| Rolle | Session-ID | Kontext | Output gesamt | Lage |\n|---|---|---|---|---|\n| engineer-a | `x` | 260 000 | 1 | Warnung — kein neues Ticket mehr annehmen |\n' > "$SPRINT/budget.md"
w="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
case "$w" in *"Loop NICHT beenden"*) ;; *) fehler="$fehler tick:warnung" ;; esac
printf '| Rolle | Session-ID | Kontext | Output gesamt | Lage |\n|---|---|---|---|---|\n| engineer-a | `x` | 360 000 | 1 | **STOPP** |\n\nSTOP engineer-a\n' > "$SPRINT/budget.md"
s1="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
s2="$(KIT_ROLE=engineer-a KIT_ROLE_LOOP=1 "$BIN/tick.sh" 2>&1)"
case "$s1" in *"Loop NICHT beenden"*) ;; *) fehler="$fehler tick:stop-ohne-schleife" ;; esac
case "$s2" in *"Loop NICHT beenden"*"restart-self"*|*"restart-self"*"Loop NICHT beenden"*) ;; *) fehler="$fehler tick:stop-unter-schleife" ;; esac
# Hook-Text (claude-code) nennt die Toolnamen
H="$(printf '{"source":"startup"}' | KIT_ROLE=engineer-a "$KIT_ROOT/adapters/claude-code/session-start.sh")"
case "$H" in *"Nie AskUserQuestion"*"CronDelete"*) ;; *) fehler="$fehler hook" ;; esac
observe "Blatt: beide Regeln · Tick Warnung/STOP/STOP unter Schleife: 'Loop NICHT beenden' · Hook nennt AskUserQuestion und CronDelete${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
