#!/usr/bin/env bash
CASE_DESC="Zwillingssperre: eine zweite lebende Instanz derselben Rolle wird abgewiesen, eine tote nicht"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$ZWILLING" 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null

sleep 300 & ZWILLING=$!          # die "erste" Instanz: ein lebender Prozess
fehler=""

o1="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-1 KIT_HOST_PID="$ZWILLING" "$BIN/register.sh" 2>&1)" || fehler="$fehler erste-Instanz-abgewiesen"
o2="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-1 KIT_HOST_PID="$ZWILLING" "$BIN/register.sh" 2>&1)" || fehler="$fehler dieselbe-Instanz-erneut-abgewiesen"
o3="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-1 KIT_HOST_PID=$$ "$BIN/tick.sh" 2>&1)"; rc3=$?
case "$o3" in *"zweite Instanz"*) ;; *) fehler="$fehler Zwilling-mit-gleicher-Session-durchgelassen" ;; esac
[ "$rc3" != 0 ] || fehler="$fehler tick-Exit-0-trotz-Zwilling"
o4="$(KIT_ROLE=engineer-b KIT_SESSION_ID=sess-2 KIT_HOST_PID=$$ "$BIN/register.sh" 2>&1)" || fehler="$fehler andere-Rolle-abgewiesen"

kill "$ZWILLING"; wait "$ZWILLING" 2>/dev/null
o5="$(KIT_ROLE=engineer-a KIT_SESSION_ID=sess-3 KIT_HOST_PID=$$ "$BIN/register.sh" 2>&1)" || fehler="$fehler tote-Instanz-blockiert"
zeilen="$(grep -c '| engineer-a |' "$SANDBOX/sprints/S-001-eval/roster.md")"
[ "$zeilen" = 1 ] || fehler="$fehler roster-hat-$zeilen-Zeilen-fuer-engineer-a"

observe "gleiche Instanz erneut: ok · Zwilling (andere PID, gleiche Session): abgewiesen, tick Exit $rc3 · andere Rolle: ok · nach Tod der ersten Instanz: uebernommen, roster 1 Zeile${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
