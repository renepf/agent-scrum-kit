#!/usr/bin/env bash
CASE_DESC="bin/tick.sh --signal meldet mit Exit 4, dass nichts anliegt; die Waechter-Schleife startet dann kein Modell; ein Statuswechsel weckt die Folgerolle sofort; ohne Schalter bleibt der Exitcode 0"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill $LOOPS 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
LOOPS=""

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
tick() { KIT_ROLE="$1" "$BIN/tick.sh" ${2:-} > /dev/null 2>&1; echo $?; }

# --- 1. Leerer Tick: mit Schalter 4, ohne Schalter 0 (bestehende Aufrufer merken nichts)
n=$((n + 1)); [ "$(tick engineer-a --signal)" = 4 ] || fail "a-leer-ohne-4:$(tick engineer-a --signal)"
n=$((n + 1)); [ "$(tick engineer-a)" = 0 ] || fail "b-ohne-Schalter-nicht-0:$(tick engineer-a)"

# --- 2. Freies Ticket in der eigenen Warteschlange: Exit 0 auch mit Schalter
sandbox_plannable 5 "src/m5/**"
sandbox_issue 5 '{"labels":["status:planned","sprint:current"]}'
n=$((n + 1)); [ "$(tick engineer-a --signal)" = 0 ] || fail "c-mit-Ticket-nicht-0"
n=$((n + 1)); [ "$(tick qa-ruthless --signal)" = 4 ] || fail "d-fremde-Warteschlange-nicht-4"

# --- 3. Ein Statuswechsel weckt die Rollen, deren Warteschlange den neuen Zustand enthaelt
rm -f "$KIT_ROOT/.role-loop"/*.wake 2>/dev/null
sandbox_plannable 6 "src/m6/**" > /dev/null
sandbox_ticket 6 backlog
plan_out="$(KIT_ROLE=product-owner "$BIN/status.sh" 6 planned "los" 2>&1)"; plan_rc=$?
n=$((n + 1)); [ "$plan_rc" = 0 ] || fail "e0-Uebergang-scheiterte:'$(printf '%s' "$plan_out" | tail -1 | head -c 100)'"
n=$((n + 1)); [ -f "$KIT_ROOT/.role-loop/engineer-a.wake" ] || fail "e-Engineer-nicht-geweckt"
n=$((n + 1)); [ ! -f "$KIT_ROOT/.role-loop/acceptance-tester.wake" ] || fail "f-falsche-Rolle-geweckt"

# --- 4. Die Schleife startet ohne Arbeit kein Modell, mit Arbeit schon
FAKE="$SANDBOX/fake-host.sh"
printf '#!/usr/bin/env bash\ndate >> "%s/host-gestartet"\nsleep 0.2\n' "$SANDBOX" > "$FAKE"; chmod +x "$FAKE"
rm -f "$SANDBOX/host-gestartet" "$KIT_ROOT/.role-loop/security-engineer.wake" "$KIT_ROOT/.role-loop/security-engineer.stop"
# Takt in die Sandkasten-kit.env, nicht in die Umgebung: kit.env wird mit set -a gelesen und
# ueberschreibt jede gleichnamige Umgebungsvariable (Falle aus dem Referenz-Loop).
printf 'KIT_TICK_INTERVAL=30\nKIT_TICK_POLL=1\n' >> "$SANDBOX/kit.env"
# Eine Rolle, fuer die dieser Fall keinen Anker gesetzt hat — sonst haelt die Zwillingssperre die Schleife an.
( KIT_LOOP_CLAUDE="$FAKE" KIT_LOOP_SLEEP=1 \
  "$KIT_ROOT/adapters/claude-code/role-loop.sh" security-engineer > /dev/null 2>&1 ) & LOOPS="$!"
sleep 4
n=$((n + 1)); [ ! -e "$SANDBOX/host-gestartet" ] || fail "g-Modell-ohne-Arbeit-gestartet"
# Eine Marke allein startet nichts: sie beendet nur das Warten, geprueft wird wieder mit dem Tick.
touch "$KIT_ROOT/.role-loop/security-engineer.wake"
sleep 3
n=$((n + 1)); [ ! -e "$SANDBOX/host-gestartet" ] || fail "h0-Marke-ohne-Arbeit-startete-Modell"
# Mit Arbeit in der eigenen Warteschlange startet die Schleife beim naechsten Durchlauf.
sandbox_plannable 7 "src/m7/**" > /dev/null
sandbox_issue 7 '{"labels":["status:rfr","sprint:current"]}'
touch "$KIT_ROOT/.role-loop/security-engineer.wake"
sleep 5
n=$((n + 1)); [ -e "$SANDBOX/host-gestartet" ] || fail "h-mit-Arbeit-nicht-gestartet"
touch "$KIT_ROOT/.role-loop/security-engineer.stop"
kill $LOOPS 2>/dev/null; wait $LOOPS 2>/dev/null; LOOPS=""
rm -f "$KIT_ROOT/.role-loop"/security-engineer.* 2>/dev/null

observe "$n Pruefungen, $falsch falsch${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ "$falsch" = 0 ]
