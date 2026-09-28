#!/usr/bin/env bash
CASE_DESC="bin/tick.sh --signal reports with exit 4 that nothing is waiting; the watchdog loop then starts no model; a status change wakes the next role at once; without the flag the exit code stays 0"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill $LOOPS 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
LOOPS=""

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
tick() { KIT_ROLE="$1" "$BIN/tick.sh" ${2:-} > /dev/null 2>&1; echo $?; }

# --- 1. An empty tick: 4 with the flag, 0 without it (existing callers notice nothing)
n=$((n + 1)); [ "$(tick engineer-a --signal)" = 4 ] || fail "a-empty-without-4:$(tick engineer-a --signal)"
n=$((n + 1)); [ "$(tick engineer-a)" = 0 ] || fail "b-without-flag-not-0:$(tick engineer-a)"

# --- 2. A free ticket in your own queue: exit 0 even with the flag
sandbox_plannable 5 "src/m5/**"
sandbox_issue 5 '{"labels":["status:planned","sprint:current"]}'
n=$((n + 1)); [ "$(tick engineer-a --signal)" = 0 ] || fail "c-with-ticket-not-0"
# A role that does not see this ticket. NOT the requirements-engineer: the loop below runs under
# that name, and a tick here would leave an anchor — then the twin lock would stop the loop and the
# case would measure the lock instead of the gate (measured, 2026-09-29).
n=$((n + 1)); [ "$(tick kit-maintainer --signal)" = 4 ] || fail "d-foreign-queue-not-4"

# --- 3. A status change wakes the roles whose queue contains the new state
rm -f "$KIT_ROOT/.role-loop"/*.wake 2>/dev/null
sandbox_plannable 6 "src/m6/**" > /dev/null
sandbox_ticket 6 backlog
plan_out="$(KIT_ROLE=product-owner "$BIN/status.sh" 6 planned "los" 2>&1)"; plan_rc=$?
n=$((n + 1)); [ "$plan_rc" = 0 ] || fail "e0-Uebergang-scheiterte:'$(printf '%s' "$plan_out" | tail -1 | head -c 100)'"
n=$((n + 1)); [ -f "$KIT_ROOT/.role-loop/engineer-a.wake" ] || fail "e-engineer-not-woken"
n=$((n + 1)); [ ! -f "$KIT_ROOT/.role-loop/kit-maintainer.wake" ] || fail "f-wrong-role-woken"

# --- 4. Without work the loop starts no model, with work it does
FAKE="$SANDBOX/fake-host.sh"
printf '#!/usr/bin/env bash\ndate >> "%s/host-started"\nsleep 0.2\n' "$SANDBOX" > "$FAKE"; chmod +x "$FAKE"
rm -f "$SANDBOX/host-started" "$KIT_ROOT/.role-loop/requirements-engineer.wake" "$KIT_ROOT/.role-loop/requirements-engineer.stop"
# The cadence into the sandbox kit.env, not into the environment: kit.env is read with set -a and
# overwrites every environment variable of the same name (a trap from the reference loop).
printf 'KIT_TICK_INTERVAL=30\nKIT_TICK_POLL=1\n' >> "$SANDBOX/kit.env"
# A role this case has set no anchor for — otherwise the twin lock stops the loop.
( KIT_LOOP_CLAUDE="$FAKE" KIT_LOOP_SLEEP=1 \
  "$KIT_ROOT/adapters/claude-code/role-loop.sh" requirements-engineer > /dev/null 2>&1 ) & LOOPS="$!"
sleep 4
n=$((n + 1)); [ ! -e "$SANDBOX/host-started" ] || fail "g-model-started-without-work"
# A mark alone starts nothing: it only ends the waiting, the check is done by the tick again.
touch "$KIT_ROOT/.role-loop/requirements-engineer.wake"
sleep 3
n=$((n + 1)); [ ! -e "$SANDBOX/host-started" ] || fail "h0-mark-without-work-started-a-model"
# With work in its own queue the loop starts on the next pass. For the requirements-engineer that
# is a ticket in the backlog — its queue is the only one that does not contain planned.
sandbox_plannable 7 "src/m7/**" > /dev/null
sandbox_issue 7 '{"labels":["status:backlog","sprint:current"]}'
touch "$KIT_ROOT/.role-loop/requirements-engineer.wake"
sleep 5
n=$((n + 1)); [ -e "$SANDBOX/host-started" ] || fail "h-with-work-not-started"
touch "$KIT_ROOT/.role-loop/requirements-engineer.stop"
kill $LOOPS 2>/dev/null; wait $LOOPS 2>/dev/null; LOOPS=""
rm -f "$KIT_ROOT/.role-loop"/requirements-engineer.* 2>/dev/null

observe "$n checks, $wrong wrong${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ "$wrong" = 0 ]
