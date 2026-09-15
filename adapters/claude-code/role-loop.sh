#!/usr/bin/env bash
# Waechter-Schleife fuer eine Rolle: startet claude und startet es neu, sobald es endet.
# Zusammen mit bin/restart-self.sh der autonome Ersatz fuer /clear: die Rolle beendet sich an einer
# Ticketgrenze selbst, die Schleife startet sie frisch, der SessionStart-Hook weckt sie.
#
#   adapters/claude-code/role-loop.sh <rolle> [--after <host-pid>]
#
# --after <pid>: bin/restart-self.sh oeffnet die Schleife in einem zellij-Tab, BEVOR sich die alte Session
#                beendet. Die Schleife wartet bis 120 s, bis unter der PID kein Host mehr lebt — sonst
#                griffe die Zwillingssperre unten und beide stuenden.
#
# Stoppen:        touch .role-loop/<rolle>.stop   (dann claude normal beenden)
# Log:            .role-loop/<rolle>.log
# Absturzschutz:  endet claude 3x in Folge nach weniger als 60 s, gibt die Schleife auf.
# Tests:          KIT_LOOP_CLAUDE (Befehl statt claude), KIT_LOOP_SLEEP (Pause zwischen Starts)
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KIT_ROOT/bin/common.sh"
set +e

R="${1:-}"; [ -n "$R" ] || die "Aufruf: role-loop.sh <rolle>"
case " $KIT_ROLES " in *" $R "*) ;; *) die "unbekannte Rolle '$R'. Erlaubt: $KIT_ROLES" ;; esac

STATE="$KIT_ROOT/.role-loop"; mkdir -p "$STATE"
LOG="$STATE/$R.log"; STOP="$STATE/$R.stop"

if [ "${2:-}" = "--after" ] && [ -n "${3:-}" ]; then
  echo "$(now) · warte auf Ende von Host-PID $3" >> "$LOG"
  for _ in $(seq 1 "${KIT_LOOP_AFTER_SECONDS:-120}"); do host_alive "$3" || break; sleep 1; done
  host_alive "$3" && die "Host-PID $3 lebt nach ${KIT_LOOP_AFTER_SECONDS:-120} s noch — nicht doppelt starten"
fi

# Keine zweite Instanz derselben Rolle.
for f in "$PID_ROLES"/*; do
  [ -f "$f" ] || continue
  p="$(basename "$f")"
  if [ "$(cat "$f")" = "$R" ] && host_alive "$p"; then
    die "Rolle $R laeuft schon (Host-PID $p). Nicht doppelt starten."
  fi
done

rm -f "$STOP"
export KIT_ROLE="$R" KIT_ROLE_LOOP=1
fast=0
echo "$(now) · Schleife gestartet fuer $R in $KIT_ROOT" >> "$LOG"
while :; do
  [ -f "$STOP" ] && { echo "$(now) · Stopp-Datei gefunden, Schleife endet" >> "$LOG"; break; }
  start=$(date +%s)
  echo "$(now) · starte claude" >> "$LOG"
  ( cd "$KIT_ROOT" && eval "${KIT_LOOP_CLAUDE:-claude -n \"$R\" --settings adapters/claude-code/settings.json --mcp-config .mcp.json}" )
  rc=$?; dur=$(( $(date +%s) - start ))
  echo "$(now) · claude beendet rc=$rc nach ${dur}s" >> "$LOG"
  [ -f "$STOP" ] && { echo "$(now) · Stopp-Datei gefunden, Schleife endet" >> "$LOG"; break; }
  if [ "$dur" -lt 60 ]; then fast=$((fast + 1)); else fast=0; fi
  if [ "$fast" -ge 3 ]; then
    echo "$(now) · 3 schnelle Abbrueche in Folge — Schleife gibt auf" >> "$LOG"
    echo "role-loop $R: 3 schnelle Abbrueche in Folge, siehe $LOG" >&2
    exit 1
  fi
  sleep "${KIT_LOOP_SLEEP:-3}"
done
