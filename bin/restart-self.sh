#!/usr/bin/env bash
# Selbst zuruecksetzen: die Rolle beendet ihren Host-Prozess, eine Waechter-Schleife startet sie frisch,
# der Start-Hook weckt sie, und sie arbeitet aus ihrer Uebergabe weiter.
#
#   bin/restart-self.sh stop|warnung|selbst|max-tickets "<einzeiler>"
#
# Bedingungen, sonst Ablehnung — und dann wird NICHTS beendet:
#   U  Uebergabe (brain.sh handover) juenger als 10 Minuten
#   T  jedes Sprint-Ticket mit owner:<rolle> steht als #<nr> in dieser Uebergabe. Mitten im Ticket
#      zuruecksetzen ist erlaubt — dann traegt die Uebergabe Stand, SHA und naechsten Schritt je Ticket.
# Weg:
#   unter der Waechter-Schleife (KIT_ROLE_LOOP=1): Host-Prozess beenden, die Schleife startet neu
#   sonst in zellij: neuen Tab "<rolle> (loop)" mit adapters/<host>/role-loop.sh <rolle> --after <pid>
#     oeffnen, erst beenden, wenn die Schleife nachweislich laeuft. Kein Tippen in fremde Panes.
#   sonst: Ablehnung — niemand wuerde neu starten.
# KIT_RESTART_DRY_RUN=1: alles pruefen und zeigen, nichts oeffnen, nichts beenden.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REASON="${1:-}"; NOTE="${2:-}"
case "$REASON" in stop|warnung|selbst|max-tickets) ;; *) die "Anlass fehlt oder unbekannt: stop | warnung | selbst | max-tickets" ;; esac
R="$(role)"
DRY="${KIT_RESTART_DRY_RUN:-0}"

HO="$(ls -t "$MEMORY_DIR/$R/handover/"*.md 2>/dev/null | head -1 || true)"
[ -n "$HO" ] || die "keine Uebergabe in memory/$R/handover/ — erst brain.sh handover"
AGE=$(( ( $(date +%s) - $(stat -f %m "$HO" 2>/dev/null || stat -c %Y "$HO") ) / 60 ))
[ "$AGE" -lt 10 ] || die "letzte Uebergabe ist $AGE min alt ($(basename "$HO")) — erst brain.sh handover, dann erneut"

"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — gehaltene Tickets nicht pruefbar, nicht raten"
HELD="$("$BIN_DIR/tickets.sh" sprint | python3 -c '
import json, sys
o = sys.argv[1]
print(" ".join(str(i["number"]) for i in json.load(sys.stdin) if o in [l["name"] for l in i["labels"]]))
' "$KIT_OWNER_PREFIX$R")" || die "Ticketliste nicht lesbar — gehaltene Tickets nicht pruefbar, nicht raten"
for n in $HELD; do
  grep -qE "#$n([^0-9]|\$)" "$HO" \
    || die "du haeltst #$n, die Uebergabe $(basename "$HO") nennt es nicht. Erst abschliessen, oder #$n mit Stand, SHA und naechstem Schritt in die Uebergabe."
done

HP="$(host_pid)"
[ -n "$HP" ] || die "Host-PID UNKNOWN (adapters/$KIT_HOST/host-pid.sh) — nichts zu beenden"
LOOP="$KIT_ROOT/adapters/$KIT_HOST/role-loop.sh"

if [ "${KIT_ROLE_LOOP:-}" = "1" ]; then
  WAY="Waechter-Schleife startet neu"
  LAYOUT=""
else
  [ -n "${ZELLIJ_SESSION_NAME:-}" ] || die "nicht unter der Waechter-Schleife und nicht in zellij — niemand wuerde neu starten. Den Menschen fragen."
  [ -x "$LOOP" ] || die "adapters/$KIT_HOST/role-loop.sh fehlt — kein Neustartweg fuer diesen Host"
  HOST_BIN="$(command -v "${KIT_HOST_BIN:-claude}" 2>/dev/null || true)"
  PATH_PREFIX=""; [ -n "$HOST_BIN" ] && PATH_PREFIX="export PATH='$(dirname "$HOST_BIN")':\"\$PATH\"; "
  mkdir -p "$KIT_ROOT/.role-loop"
  LAYOUT="$KIT_ROOT/.role-loop/$R.kdl"
  RUN="${PATH_PREFIX}cd '$KIT_ROOT' && exec '$LOOP' '$R' --after $HP"
  SH_BIN="${SHELL:-/bin/sh}"
  printf 'layout {\n  pane command="%s" {\n    args "-lc" "%s"\n  }\n}\n' "$SH_BIN" "$(printf '%s' "$RUN" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$LAYOUT"
  WAY="neuer zellij-Tab '$R (loop)' in $ZELLIJ_SESSION_NAME, Layout ${LAYOUT#$KIT_ROOT/}"
fi

if [ "$DRY" = "1" ]; then
  echo "TROCKENLAUF restart-self $R ($REASON): Uebergabe $(basename "$HO") $AGE min, gehalten: ${HELD:-keins}, Host-PID $HP"
  echo "Weg: $WAY"
  [ -z "$LAYOUT" ] || cat "$LAYOUT"
  exit 0
fi

[ ! -f "$CURRENT_FILE" ] || KIT_ROLE="$R" "$BIN_DIR/say.sh" "Neustart ($REASON)" <<MSG > /dev/null
${NOTE:-Selbst-Neustart.} Uebergabe: memory/$R/handover/$(basename "$HO"). Gehalten: ${HELD:-keins}. Weg: $WAY. Zurueck in wenigen Sekunden.
MSG

if [ -n "$LAYOUT" ]; then
  zellij --session "$ZELLIJ_SESSION_NAME" action new-tab --name "$R (loop)" --layout "$LAYOUT" \
    || die "zellij-Tab nicht geoeffnet — Prozess bleibt, den Menschen fragen"
  # Erst beenden, wenn die Schleife nachweislich laeuft — sonst waere die Rolle weg.
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "role-loop.sh $R --after $HP" > /dev/null && break; sleep 1; done
  pgrep -f "role-loop.sh $R --after $HP" > /dev/null \
    || die "Tab geoeffnet, aber keine Schleife fuer $R nach 10 s — Prozess bleibt, Tab '$R (loop)' pruefen"
fi
nohup bash -c "sleep ${KIT_RESTART_DELAY:-3}; kill -TERM $HP" > /dev/null 2>&1 &
echo "Host-Prozess $HP endet in ${KIT_RESTART_DELAY:-3} s — $WAY"
