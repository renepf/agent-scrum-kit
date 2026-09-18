#!/usr/bin/env bash
CASE_DESC="role rules: never end your own loop, never ask a question that waits for input — in the sheet, in the tick text and in the hook"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
errors=""
C="$KIT_ROOT/roles/_COMMON.md"
grep -q 'Never end your own loop' "$C" || errors="$errors sheet:loop"
grep -q 'Never ask a question that waits for input' "$C" || errors="$errors sheet:question"
# The tick on a warning and on STOP, with and without the watchdog loop
printf '| Role | Session-ID | Context | Output total | State |\n|---|---|---|---|---|\n| engineer-a | `x` | 260 000 | 1 | warning — take no new ticket |\n' > "$SPRINT/budget.md"
w="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
case "$w" in *"Do NOT end your loop"*) ;; *) errors="$errors tick:warning" ;; esac
printf '| Role | Session-ID | Context | Output total | State |\n|---|---|---|---|---|\n| engineer-a | `x` | 360 000 | 1 | **STOP** |\n\nSTOP engineer-a\n' > "$SPRINT/budget.md"
s1="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
s2="$(KIT_ROLE=engineer-a KIT_ROLE_LOOP=1 "$BIN/tick.sh" 2>&1)"
case "$s1" in *"Do NOT end your loop"*) ;; *) errors="$errors tick:stop-without-loop" ;; esac
case "$s2" in *"Do NOT end your loop"*"restart-self"*|*"restart-self"*"Do NOT end your loop"*) ;; *) errors="$errors tick:stop-under-loop" ;; esac
# The hook text (claude-code) names the tool names
H="$(printf '{"source":"startup"}' | KIT_ROLE=engineer-a "$KIT_ROOT/adapters/claude-code/session-start.sh")"
case "$H" in *"Never AskUserQuestion"*"CronDelete"*) ;; *) errors="$errors hook" ;; esac
observe "sheet: both rules · tick warning/STOP/STOP under the loop: 'Do NOT end your loop' · the hook names AskUserQuestion and CronDelete${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
