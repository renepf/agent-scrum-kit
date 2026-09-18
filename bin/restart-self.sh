#!/usr/bin/env bash
# Reset yourself: the role ends its host process, a watchdog loop starts it fresh,
# the start hook wakes it, and it carries on from its handover.
#
#   bin/restart-self.sh stop|warning|self|max-tickets "<one-liner>"
#
# Conditions, otherwise a rejection — and then NOTHING is ended:
#   H  a handover (brain.sh handover) younger than 10 minutes
#   T  every sprint ticket with owner:<role> appears as #<nr> in that handover. Resetting in the
#      middle of a ticket is allowed — the handover then carries state, SHA and next step per ticket.
# Path:
#   under the watchdog loop (KIT_ROLE_LOOP=1): end the host process, the loop starts it again
#   otherwise in zellij: open a new tab "<role> (loop)" with adapters/<host>/role-loop.sh <role> --after <pid>,
#     end only once the loop demonstrably runs. No typing into other people's panes.
#   otherwise: rejection — nobody would start it again.
# KIT_RESTART_DRY_RUN=1: check and show everything, open nothing, end nothing.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REASON="${1:-}"; NOTE="${2:-}"
case "$REASON" in stop|warning|self|max-tickets) ;; *) die "reason missing or unknown: stop | warning | self | max-tickets" ;; esac
R="$(role)"
DRY="${KIT_RESTART_DRY_RUN:-0}"

HO="$(ls -t "$MEMORY_DIR/$R/handover/"*.md 2>/dev/null | head -1 || true)"
[ -n "$HO" ] || die "no handover in memory/$R/handover/ — run brain.sh handover first"
AGE=$(( ( $(date +%s) - $(stat -f %m "$HO" 2>/dev/null || stat -c %Y "$HO") ) / 60 ))
[ "$AGE" -lt 10 ] || die "the last handover is $AGE min old ($(basename "$HO")) — run brain.sh handover first, then try again"

"$BIN_DIR/preflight.sh" > /dev/null || die "preflight failed — held tickets not checkable, do not guess"
HELD="$("$BIN_DIR/tickets.sh" sprint | python3 -c '
import json, sys
o = sys.argv[1]
print(" ".join(str(i["number"]) for i in json.load(sys.stdin) if o in [l["name"] for l in i["labels"]]))
' "$KIT_OWNER_PREFIX$R")" || die "ticket list not readable — held tickets not checkable, do not guess"
for n in $HELD; do
  grep -qE "#$n([^0-9]|\$)" "$HO" \
    || die "you hold #$n, the handover $(basename "$HO") does not name it. Finish it first, or put #$n with state, SHA and next step into the handover."
done

HP="$(host_pid)"
[ -n "$HP" ] || die "host PID UNKNOWN (adapters/$KIT_HOST/host-pid.sh) — nothing to end"
LOOP="$KIT_ROOT/adapters/$KIT_HOST/role-loop.sh"

if [ "${KIT_ROLE_LOOP:-}" = "1" ]; then
  WAY="watchdog loop starts it again"
  LAYOUT=""
else
  [ -n "${ZELLIJ_SESSION_NAME:-}" ] || die "not under the watchdog loop and not in zellij — nobody would start it again. Ask the human."
  [ -x "$LOOP" ] || die "adapters/$KIT_HOST/role-loop.sh is missing — no restart path for this host"
  HOST_BIN="$(command -v "${KIT_HOST_BIN:-claude}" 2>/dev/null || true)"
  PATH_PREFIX=""; [ -n "$HOST_BIN" ] && PATH_PREFIX="export PATH='$(dirname "$HOST_BIN")':\"\$PATH\"; "
  mkdir -p "$KIT_ROOT/.role-loop"
  LAYOUT="$KIT_ROOT/.role-loop/$R.kdl"
  RUN="${PATH_PREFIX}cd '$KIT_ROOT' && exec '$LOOP' '$R' --after $HP"
  SH_BIN="${SHELL:-/bin/sh}"
  printf 'layout {\n  pane command="%s" {\n    args "-lc" "%s"\n  }\n}\n' "$SH_BIN" "$(printf '%s' "$RUN" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$LAYOUT"
  WAY="new zellij tab '$R (loop)' in $ZELLIJ_SESSION_NAME, layout ${LAYOUT#$KIT_ROOT/}"
fi

if [ "$DRY" = "1" ]; then
  echo "DRY RUN restart-self $R ($REASON): handover $(basename "$HO") $AGE min, held: ${HELD:-none}, host PID $HP"
  echo "Path: $WAY"
  [ -z "$LAYOUT" ] || cat "$LAYOUT"
  exit 0
fi

[ ! -f "$CURRENT_FILE" ] || KIT_ROLE="$R" "$BIN_DIR/say.sh" "Restart ($REASON)" <<MSG > /dev/null
${NOTE:-Self restart.} Handover: memory/$R/handover/$(basename "$HO"). Held: ${HELD:-none}. Path: $WAY. Back in a few seconds.
MSG

if [ -n "$LAYOUT" ]; then
  zellij --session "$ZELLIJ_SESSION_NAME" action new-tab --name "$R (loop)" --layout "$LAYOUT" \
    || die "zellij tab not opened — the process stays, ask the human"
  # End only once the loop demonstrably runs — otherwise the role would be gone.
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "role-loop.sh $R --after $HP" > /dev/null && break; sleep 1; done
  pgrep -f "role-loop.sh $R --after $HP" > /dev/null \
    || die "tab opened, but no loop for $R after 10 s — the process stays, check the tab '$R (loop)'"
fi
nohup bash -c "sleep ${KIT_RESTART_DELAY:-3}; kill -TERM $HP" > /dev/null 2>&1 &
echo "host process $HP ends in ${KIT_RESTART_DELAY:-3} s — $WAY"
