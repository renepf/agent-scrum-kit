#!/usr/bin/env bash
CASE_DESC="eine neu vergebene PID (anderer Prozess) gilt nicht als laufende Rolle: Tick raeumt den Anker weg, Zwillingssperre und Schleife blockieren nicht"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$FREMD" 2>/dev/null; rm -rf "$KIT_ROOT/.pid-roles/$FREMD" "$KIT_ROOT/.pid-roles/999999" "$KIT_ROOT/.role-loop"; sandbox_cleanup' EXIT
SPRINT="$(sandbox_sprint)"
# "sleep" ist der fremde Prozess, der eine alte Anker-PID uebernommen hat. Host ist nur "bash"-los: wir
# erklaeren per KIT_HOST_ALIVE_NAME einen Namen zum Host, den sleep nicht traegt.
sleep 300 & FREMD=$!
export KIT_HOST_ALIVE_NAME="nicht-sleep"
mkdir -p "$KIT_ROOT/.pid-roles"
echo engineer-a > "$KIT_ROOT/.pid-roles/$FREMD"     # neu vergeben: lebt, ist aber kein Host
echo engineer-a > "$KIT_ROOT/.pid-roles/999999"     # tot
printf '%s|%s|%s\n' "alt" "$FREMD" "$(date +%s)" > "$SPRINT/.lease-engineer-a"
fehler=""
out="$(KIT_ROLE=engineer-a KIT_SESSION_ID=neu KIT_HOST_PID=$$ "$BIN/tick.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] || fehler="$fehler tick-exit-$rc"
case "$out" in *"zweite Instanz"*) fehler="$fehler fremder-Prozess-als-Zwilling" ;; esac
[ ! -f "$KIT_ROOT/.pid-roles/$FREMD" ] || fehler="$fehler anker-neu-vergeben-bleibt"
[ ! -f "$KIT_ROOT/.pid-roles/999999" ] || fehler="$fehler anker-tot-bleibt"
grep -q '| engineer-a | neu |' "$SPRINT/roster.md" || fehler="$fehler nicht-registriert"
# Schleife: fremder Prozess mit Anker darf den Start nicht verhindern
echo engineer-b > "$KIT_ROOT/.pid-roles/$FREMD"
lo="$(KIT_LOOP_CLAUDE='touch "$KIT_ROOT/.role-loop/engineer-b.stop"' KIT_LOOP_SLEEP=0 "$KIT_ROOT/adapters/claude-code/role-loop.sh" engineer-b 2>&1)"; lr=$?
case "$lo" in *"laeuft schon"*) fehler="$fehler schleife-blockiert" ;; esac
observe "neu vergebene PID + tote PID: Tick Exit $rc, beide Anker weg, registriert · Schleife startet trotz fremdem Anker (Exit $lr)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
