#!/usr/bin/env bash
# SessionStart hook for claude-code. Gives a kit role its assignment back after a start, /clear or
# resume. Without a role (no KIT_ROLE, no anchor) it prints nothing — other sessions
# notice nothing.
#
#   session-start.sh          context mode: JSON with additionalContext on stdout
#   session-start.sh --wake   wake mode for a second hook entry with asyncRewake:
#                             on startup|clear|resume, text on stderr and exit 2 — that wakes the
#                             session and makes the text the next turn, without any input.
#                             On compact and fork it stays silent (reference measurement 2026-09-11: fork
#                             fired additionally and would have woken it twice).
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT="$(cat 2>/dev/null || true)"
SOURCE="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("source","?"))
except Exception: print("?")' 2>/dev/null)"

R="${KIT_ROLE:-}"
if [ -z "$R" ]; then
  HP="${KIT_HOST_PID:-$("$KIT_ROOT/adapters/claude-code/host-pid.sh" 2>/dev/null || true)}"
  [ -n "$HP" ] && [ -f "$KIT_ROOT/.pid-roles/$HP" ] && R="$(cat "$KIT_ROOT/.pid-roles/$HP")"
fi
[ -n "$R" ] || exit 0
"$KIT_ROOT/adapters/claude-code/is-background.sh" && exit 0

# Every engineer instance reads the same sheet; the role name in KIT_ROLE tells them apart.
case "$R" in engineer-*) FILE=engineer.md ;; *) FILE="$R.md" ;; esac
[ -f "$KIT_ROOT/roles/$FILE" ] || exit 0
case "$R" in product-owner|acceptance-tester|merge-gate) IV=10m ;; *) IV=5m ;; esac
EXTRA=""; [ "$R" = "watchdog" ] && EXTRA=" Afterwards bin/budget.sh, four looks, bin/commit.sh."

CTX="AGENT-SCRUM-KIT — ROLE ANCHOR (SessionStart: $SOURCE)
You are the role **$R**. That holds after /clear too: your context is new, your role is not.

At once, in this order:
1. Read roles/_COMMON.md and roles/$FILE.
2. Run bin/tick.sh. It recognises the new session, registers you again and shows your last handover.
3. Carry on from the last handover.
4. Check whether your loop is running (CronList). If not:
   /loop $IV Run bin/tick.sh. If nothing is waiting for you, end the round. Otherwise work your role per roles/$FILE: one ticket at a time, picking up means setting the In status immediately, no subagent.$EXTRA

Never AskUserQuestion and never CronDelete for your own loop: ask only via bin/say.sh with @owner, name the safe default, keep ticking.
The scripts know your role even without KIT_ROLE, through the anchor in .pid-roles/."

if [ "${1:-}" = "--wake" ]; then
  case "$SOURCE" in startup|clear|resume) ;; *) exit 0 ;; esac
  sleep "${KIT_WAKE_DELAY:-2}"
  printf '%s\n' "$CTX" >&2
  exit 2
fi

python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$CTX"
