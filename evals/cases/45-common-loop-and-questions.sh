#!/usr/bin/env bash
CASE_DESC="Rollenregeln: den eigenen Loop nie beenden, nie eine Rueckfrage, die auf Eingabe wartet — im Blatt, im Tick-Text und im Hook"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
fehler=""
C="$KIT_ROOT/roles/_COMMON.md"
grep -q 'Never end your own loop' "$C" || fehler="$fehler blatt:loop"
grep -q 'Never ask a question that waits for input' "$C" || fehler="$fehler blatt:rueckfrage"
# Tick bei Warnung und bei STOP, mit und ohne Waechter-Schleife
printf '| Role | Session-ID | Context | Output total | State |\n|---|---|---|---|---|\n| engineer-a | `x` | 260 000 | 1 | warning — take no new ticket |\n' > "$SPRINT/budget.md"
w="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
case "$w" in *"Do NOT end your loop"*) ;; *) fehler="$fehler tick:warnung" ;; esac
printf '| Role | Session-ID | Context | Output total | State |\n|---|---|---|---|---|\n| engineer-a | `x` | 360 000 | 1 | **STOP** |\n\nSTOP engineer-a\n' > "$SPRINT/budget.md"
s1="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
s2="$(KIT_ROLE=engineer-a KIT_ROLE_LOOP=1 "$BIN/tick.sh" 2>&1)"
case "$s1" in *"Do NOT end your loop"*) ;; *) fehler="$fehler tick:stop-ohne-schleife" ;; esac
case "$s2" in *"Do NOT end your loop"*"restart-self"*|*"restart-self"*"Do NOT end your loop"*) ;; *) fehler="$fehler tick:stop-unter-schleife" ;; esac
# Hook-Text (claude-code) nennt die Toolnamen
H="$(printf '{"source":"startup"}' | KIT_ROLE=engineer-a "$KIT_ROOT/adapters/claude-code/session-start.sh")"
case "$H" in *"Never AskUserQuestion"*"CronDelete"*) ;; *) fehler="$fehler hook" ;; esac
observe "Blatt: beide Regeln · Tick Warnung/STOP/STOP unter Schleife: 'Do NOT end your loop' · Hook nennt AskUserQuestion und CronDelete${fehler:+ · FEHLER:$fehler}"
echo "OBSERVED: $OBSERVED"
[ -z "$fehler" ]
