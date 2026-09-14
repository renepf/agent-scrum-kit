#!/usr/bin/env bash
CASE_DESC="Hintergrund-Session mit geerbter Rolle: Hook schweigt, Tick endet mit Exit 3 ohne Anker; eine normale Kind-Umgebung bleibt Rolle"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'rm -f "$KIT_ROOT/.pid-roles/4711"; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
sed -i '' 's/^KIT_HOST="test-fixture"/KIT_HOST="claude-code"/' "$KIT_ENV_FILE"
H="$KIT_ROOT/adapters/claude-code/session-start.sh"
fehler=""
h1="$(printf '{"source":"startup"}' | CLAUDE_CODE_SESSION_KIND=bg KIT_ROLE=engineer-a "$H" 2>&1)"; r1=$?
w1="$(printf '{"source":"startup"}' | CLAUDE_CODE_SESSION_KIND=bg KIT_ROLE=engineer-a KIT_WAKE_DELAY=0 "$H" --wake 2>&1)"; rw=$?
[ -z "$h1" ] && [ "$r1" = 0 ] && [ -z "$w1" ] && [ "$rw" = 0 ] || fehler="$fehler hook-nicht-still"
t1="$(CLAUDE_CODE_SESSION_KIND=bg KIT_ROLE=engineer-a KIT_HOST_PID=4711 KIT_SESSION_ID=bg "$BIN/tick.sh" 2>&1)"; rt=$?
[ "$rt" = 3 ] || fehler="$fehler tick-exit-$rt"
[ ! -f "$KIT_ROOT/.pid-roles/4711" ] || fehler="$fehler anker-geschrieben"
# Gegenprobe: CLAUDE_CODE_CHILD_SESSION=1 steht in jeder Werkzeug-Umgebung — das darf NICHT sperren.
h2="$(printf '{"source":"startup"}' | CLAUDE_CODE_CHILD_SESSION=1 KIT_ROLE=engineer-a "$H" 2>&1)"
case "$h2" in *"Rolle **engineer-a**"*) ;; *) fehler="$fehler kind-umgebung-gesperrt" ;; esac
observe "bg: Hook 0 Bytes (Kontext und --wake), Tick Exit $rt, kein Anker · CLAUDE_CODE_CHILD_SESSION=1: Hook liefert Rolle${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
