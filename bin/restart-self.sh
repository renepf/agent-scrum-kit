#!/usr/bin/env bash
# Autonomer Kontext-Reset: die Rolle beendet ihren Host-Prozess an einer Ticketgrenze selbst,
# die Waechter-Schleife (adapters/<host>/role-loop.sh) startet sie frisch, der Start-Hook weckt
# sie, und sie arbeitet aus ihrer Uebergabe weiter.
#
#   bin/restart-self.sh stop|max-tickets|warnung "<einzeiler>"
#
# Lehnt ab, solange eine Bedingung fehlt — und beendet dann NICHTS:
#   1. Anlass: stop (Budget-STOP) · max-tickets (KIT_MAX_TICKETS erreicht) · warnung
#   2. die Session laeuft unter der Waechter-Schleife (KIT_ROLE_LOOP=1) — sonst waere sie danach weg
#   3. frische Uebergabe: brain.sh handover juenger als 10 Minuten
#   4. Ticketgrenze: kein offenes Sprint-Ticket traegt owner:<rolle>
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REASON="${1:-}"; NOTE="${2:-}"
case "$REASON" in stop|max-tickets|warnung) ;; *) die "Anlass fehlt oder unbekannt: stop | max-tickets | warnung" ;; esac
R="$(role)"

[ "${KIT_ROLE_LOOP:-}" = "1" ] || die "Session laeuft nicht unter adapters/$KIT_HOST/role-loop.sh — ein Selbst-Beenden wuerde sie nicht neu starten. Den Menschen fragen."

HO="$(ls -t "$MEMORY_DIR/$R/handover/"*.md 2>/dev/null | head -1 || true)"
[ -n "$HO" ] || die "keine Uebergabe in memory/$R/handover/ — erst brain.sh handover"
AGE=$(( ( $(date +%s) - $(stat -f %m "$HO" 2>/dev/null || stat -c %Y "$HO") ) / 60 ))
[ "$AGE" -lt 10 ] || die "letzte Uebergabe ist $AGE min alt ($(basename "$HO")) — erst brain.sh handover, dann erneut"

"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — Ticketgrenze nicht pruefbar, nicht raten"
HELD="$("$BIN_DIR/tickets.sh" sprint | python3 -c '
import json, sys
o = sys.argv[1]
print(" ".join(str(i["number"]) for i in json.load(sys.stdin) if o in [l["name"] for l in i["labels"]]))
' "$KIT_OWNER_PREFIX$R")" || die "Ticketliste nicht lesbar — Ticketgrenze nicht pruefbar, nicht raten"
[ -z "$HELD" ] || die "keine Ticketgrenze: du haeltst noch #$HELD ($KIT_OWNER_PREFIX$R). Erst weiterreichen oder zurueckgeben."

HP="$(host_pid)"
[ -n "$HP" ] || die "Host-PID UNKNOWN (adapters/$KIT_HOST/host-pid.sh) — nichts zu beenden"

[ ! -f "$CURRENT_FILE" ] || KIT_ROLE="$R" "$BIN_DIR/say.sh" "Neustart ($REASON)" <<MSG > /dev/null
${NOTE:-Selbst-Neustart an der Ticketgrenze.} Uebergabe: memory/$R/handover/$(basename "$HO"). Zurueck in wenigen Sekunden.
MSG

if [ "${KIT_RESTART_DRY_RUN:-}" = "1" ]; then
  echo "DRY-RUN: wuerde Host-Prozess $HP in 3 s beenden"
  exit 0
fi
nohup bash -c "sleep 3; kill -TERM $HP" > /dev/null 2>&1 &
echo "Host-Prozess $HP endet in 3 s — die Waechter-Schleife startet $R frisch"
