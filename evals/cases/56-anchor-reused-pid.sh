#!/usr/bin/env bash
CASE_DESC="a reassigned PID (another process) does not count as a running role: the tick clears the anchor away, the twin lock and the loop do not block"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$FOREIGN" 2>/dev/null; rm -rf "$KIT_ROOT/.pid-roles/$FOREIGN" "$KIT_ROOT/.pid-roles/999999" "$KIT_ROOT/.role-loop"; sandbox_cleanup' EXIT
SPRINT="$(sandbox_sprint)"
# "sleep" is the foreign process that took over an old anchor PID. We declare a name to be the host
# through KIT_HOST_ALIVE_NAME that sleep does not carry.
sleep 300 & FOREIGN=$!
export KIT_HOST_ALIVE_NAME="not-sleep"
mkdir -p "$KIT_ROOT/.pid-roles"
echo engineer-a > "$KIT_ROOT/.pid-roles/$FOREIGN"     # reassigned: alive, but not a host
echo engineer-a > "$KIT_ROOT/.pid-roles/999999"     # tot
printf '%s|%s|%s\n' "alt" "$FOREIGN" "$(date +%s)" > "$SPRINT/.lease-engineer-a"
errors=""
out="$(KIT_ROLE=engineer-a KIT_SESSION_ID=neu KIT_HOST_PID=$$ "$BIN/tick.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] || errors="$errors tick-exit-$rc"
case "$out" in *"second instance"*) errors="$errors foreign-process-as-a-twin" ;; esac
[ ! -f "$KIT_ROOT/.pid-roles/$FOREIGN" ] || errors="$errors reassigned-anchor-stays"
[ ! -f "$KIT_ROOT/.pid-roles/999999" ] || errors="$errors dead-anchor-stays"
grep -q '| engineer-a | neu |' "$SPRINT/roster.md" || errors="$errors not-registered"
# The loop: a foreign process with an anchor must not prevent the start.
# Since the loop ticks first and starts a model only when there is work (case 35), engineer-b needs a
# free ticket — otherwise the loop waits for KIT_TICK_INTERVAL and the fake host never creates the
# stop file. What is checked here is the twin lock, not the model start.
echo engineer-b > "$KIT_ROOT/.pid-roles/$FOREIGN"
sandbox_plannable 77 "src/m77/**" > /dev/null
sandbox_issue 77 '{"labels":["status:planned","sprint:current"]}'
lo="$(KIT_LOOP_CLAUDE='touch "$KIT_ROOT/.role-loop/engineer-b.stop"' KIT_LOOP_SLEEP=0 "$KIT_ROOT/adapters/claude-code/role-loop.sh" engineer-b 2>&1)"; lr=$?
case "$lo" in *"is already running"*) errors="$errors loop-blocked" ;; esac
observe "a reassigned PID + a dead PID: tick exit $rc, both anchors gone, registered · the loop starts despite a foreign anchor (exit $lr)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
