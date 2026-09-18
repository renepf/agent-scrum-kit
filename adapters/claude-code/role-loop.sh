#!/usr/bin/env bash
# Watchdog loop for one role: starts claude and starts it again as soon as it ends.
# Together with bin/restart-self.sh the autonomous replacement for /clear: the role ends itself at a
# ticket boundary, the loop starts it fresh, the SessionStart hook wakes it.
#
#   adapters/claude-code/role-loop.sh <role> [--after <host-pid>]
#
# --after <pid>: bin/restart-self.sh opens the loop in a zellij tab BEFORE the old session
#                ends. The loop waits up to 120 s until no host lives under that PID — otherwise
#                the twin lock below would bite and both would stand still.
#
# Stopping:       touch .role-loop/<role>.stop   (then end claude normally)
# Log:            .role-loop/<role>.log
# Crash guard:    if claude ends 3 times in a row after less than 60 s, the loop gives up.
# Tests:          KIT_LOOP_CLAUDE (a command instead of claude), KIT_LOOP_SLEEP (pause between starts)
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KIT_ROOT/bin/common.sh"
set +e

R="${1:-}"; [ -n "$R" ] || die "usage: role-loop.sh <role>"
case " $KIT_ROLES " in *" $R "*) ;; *) die "unknown role '$R'. Allowed: $KIT_ROLES" ;; esac

STATE="$KIT_ROOT/.role-loop"; mkdir -p "$STATE"
LOG="$STATE/$R.log"; STOP="$STATE/$R.stop"

if [ "${2:-}" = "--after" ] && [ -n "${3:-}" ]; then
  echo "$(now) · waiting for host PID $3 to end" >> "$LOG"
  for _ in $(seq 1 "${KIT_LOOP_AFTER_SECONDS:-120}"); do host_alive "$3" || break; sleep 1; done
  host_alive "$3" && die "host PID $3 still alive after ${KIT_LOOP_AFTER_SECONDS:-120} s — do not start twice"
fi

# No second instance of the same role.
for f in "$PID_ROLES"/*; do
  [ -f "$f" ] || continue
  p="$(basename "$f")"
  if [ "$(cat "$f")" = "$R" ] && host_alive "$p"; then
    die "role $R is already running (host PID $p). Do not start twice."
  fi
done

rm -f "$STOP"
export KIT_ROLE="$R" KIT_ROLE_LOOP=1
fast=0
echo "$(now) · loop started for $R in $KIT_ROOT" >> "$LOG"
WAKE="$STATE/$R.wake"
while :; do
  [ -f "$STOP" ] && { echo "$(now) · stop file found, the loop ends" >> "$LOG"; break; }
  # No model without work: the tick is bash and costs no tokens, an empty model round
  # costs a whole context window. Exit 4 means "nothing for you".
  rm -f "$WAKE"
  KIT_ROLE="$R" "$KIT_ROOT/bin/tick.sh" --signal >> "$LOG" 2>&1; trc=$?
  if [ "$trc" = 4 ]; then
    waited=0
    while [ "$waited" -lt "${KIT_TICK_INTERVAL:-300}" ]; do
      [ -f "$STOP" ] && break
      [ -f "$WAKE" ] && { echo "$(now) · wake mark, starting at once" >> "$LOG"; break; }
      sleep "${KIT_TICK_POLL:-10}"; waited=$((waited + ${KIT_TICK_POLL:-10}))
    done
    continue
  fi
  start=$(date +%s)
  echo "$(now) · starting claude (tick code $trc)" >> "$LOG"
  ( cd "$KIT_ROOT" && eval "${KIT_LOOP_CLAUDE:-claude -n \"$R\" --settings adapters/claude-code/settings.json --mcp-config .mcp.json}" )
  rc=$?; dur=$(( $(date +%s) - start ))
  echo "$(now) · claude ended rc=$rc after ${dur}s" >> "$LOG"
  [ -f "$STOP" ] && { echo "$(now) · stop file found, the loop ends" >> "$LOG"; break; }
  if [ "$dur" -lt 60 ]; then fast=$((fast + 1)); else fast=0; fi
  if [ "$fast" -ge 3 ]; then
    echo "$(now) · 3 fast aborts in a row — the loop gives up" >> "$LOG"
    echo "role-loop $R: 3 fast aborts in a row, see $LOG" >&2
    exit 1
  fi
  sleep "${KIT_LOOP_SLEEP:-3}"
done
