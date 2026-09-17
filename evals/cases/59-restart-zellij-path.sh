#!/usr/bin/env bash
CASE_DESC="zellij-Weg ohne Waechter-Schleife: restart-self oeffnet einen Tab mit role-loop.sh --after <pid>, beendet erst, wenn die Schleife laeuft; die Schleife wartet auf das Ende und startet dann; scheitert zellij, wird nichts beendet"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox
F="$SANDBOX/fakebin"; mkdir -p "$F"
trap 'kill "$ALT" "$ALT2" 2>/dev/null; pkill -f "role-loop.sh engineer-a --after" 2>/dev/null; rm -rf "$KIT_ROOT/.role-loop"; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
# Der zellij-Weg startet adapters/<host>/role-loop.sh — der Sandkasten braucht einen Host, der eine Schleife hat.
sed -i '' 's/^KIT_HOST="test-fixture"/KIT_HOST="claude-code"/' "$KIT_ENV_FILE"
# Vorgetaeuschtes zellij: "action new-tab --layout <datei>" startet den Pane-Befehl aus der Layout-Datei im Hintergrund.
cat > "$F/zellij" <<'Z'
#!/usr/bin/env bash
echo "zellij $*" >> "$ZELLIJ_LOG"
[ "${FAKE_ZELLIJ_FAIL:-0}" = 1 ] && exit 1
layout=""; while [ $# -gt 0 ]; do [ "$1" = "--layout" ] && layout="$2"; shift; done
[ -n "$layout" ] || exit 0
run="$(python3 - "$layout" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r'args "-lc" "((?:[^"\\]|\\.)*)"', t)
print(m.group(1).replace('\\"', '"').replace('\\\\', '\\'))
PY
)"
nohup bash -c "$run" >> "$ZELLIJ_LOG.pane" 2>&1 &
Z
chmod +x "$F/zellij"
# Der vorgetaeuschte Host muss "claude" heissen: host_alive des claude-code-Adapters prueft den Prozessnamen.
# Hiesse er "sleep", galte er sofort als tot und die Schleife wartete nicht — der Fall bewiese das Warten nicht.
ln -sf "$(command -v sleep)" "$F/claude"
export PATH="$F:$PATH" ZELLIJ_LOG="$SANDBOX/zellij.log" ZELLIJ_SESSION_NAME="kit-eval" SHELL=/bin/bash
: > "$ZELLIJ_LOG"
"$F/claude" 300 & ALT=$!
export KIT_ROLE=engineer-a KIT_HOST_PID="$ALT" KIT_RESTART_DELAY=1 KIT_LOOP_AFTER_SECONDS=20 KIT_LOOP_SLEEP=0
unset KIT_ROLE_LOOP
# Die "neue Session" der Schleife: haelt fest, dass sie lief, und setzt die Stopp-Datei.
export KIT_LOOP_CLAUDE='date +%s >> "$KIT_ROOT/.role-loop/engineer-a.gestartet"; touch "$KIT_ROOT/.role-loop/engineer-a.stop"'
# Seit die Schleife erst tickt und nur bei Arbeit startet (Fall 35), braucht engineer-a ein freies Ticket —
# sonst wartet sie bis KIT_TICK_INTERVAL und startet den Host nie. Geprueft wird hier der Neustartweg.
sandbox_plannable 59 "src/m59/**" > /dev/null
sandbox_issue 59 '{"labels":["status:planned","sprint:current"]}'
"$BIN/brain.sh" handover "Stand 2026-09-15" <<<'Kein Ticket offen.' > /dev/null
fehler=""
d="$(KIT_RESTART_DRY_RUN=1 "$BIN/restart-self.sh" stop 2>&1)"
case "$d" in *"zellij-Tab 'engineer-a (loop)'"*"role-loop.sh' 'engineer-a' --after $ALT"*) ;; *) fehler="$fehler trockenlauf:'$(echo "$d" | tr '\n' ' ' | cut -c1-160)'" ;; esac
[ ! -s "$ZELLIJ_LOG" ] || fehler="$fehler trockenlauf-rief-zellij"
t0=$(date +%s)
o="$("$BIN/restart-self.sh" stop 2>&1)"; rc=$?
[ "$rc" = 0 ] || fehler="$fehler exit-$rc:'$o'"
grep -q "action new-tab --name engineer-a (loop) --layout" "$ZELLIJ_LOG" || fehler="$fehler kein-new-tab"
for _ in $(seq 1 25); do kill -0 "$ALT" 2>/dev/null || break; sleep 1; done
kill -0 "$ALT" 2>/dev/null && fehler="$fehler alter-host-lebt"
for _ in $(seq 1 25); do [ -f "$KIT_ROOT/.role-loop/engineer-a.gestartet" ] && break; sleep 1; done
[ -f "$KIT_ROOT/.role-loop/engineer-a.gestartet" ] || fehler="$fehler schleife-startete-nicht"
L="$KIT_ROOT/.role-loop/engineer-a.log"
w="$(grep -n "warte auf Ende von Host-PID $ALT" "$L" 2>/dev/null | head -1 | cut -d: -f1)"; s="$(grep -n 'starte claude' "$L" 2>/dev/null | head -1 | cut -d: -f1)"
[ -n "$w" ] && [ -n "$s" ] && [ "$w" -lt "$s" ] || fehler="$fehler reihenfolge(warte=$w,start=$s)"
# zellij scheitert: nichts wird beendet
rm -rf "$KIT_ROOT/.role-loop"
"$F/claude" 300 & ALT2=$!
o2="$(FAKE_ZELLIJ_FAIL=1 KIT_HOST_PID="$ALT2" "$BIN/restart-self.sh" stop 2>&1)"; rc2=$?
sleep 2
kill -0 "$ALT2" 2>/dev/null || fehler="$fehler zellij-fehler-beendete-trotzdem"
[ "$rc2" != 0 ] || fehler="$fehler zellij-fehler-exit0"
observe "Trockenlauf: Tab mit role-loop.sh engineer-a --after $ALT, zellij nicht gerufen · echt: Tab geoeffnet, alter Host beendet, Schleife wartete und startete ($(( $(date +%s) - t0 )) s) · zellij scheitert: Exit $rc2, Host lebt${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
