#!/usr/bin/env bash
CASE_DESC="the zellij path without a watchdog loop: restart-self opens a tab with role-loop.sh --after <pid> and ends only once the loop runs; the loop waits for the end and then starts; if zellij fails, nothing is ended"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox
F="$SANDBOX/fakebin"; mkdir -p "$F"
trap 'kill "$ALT" "$ALT2" 2>/dev/null; pkill -f "role-loop.sh engineer-a --after" 2>/dev/null; rm -rf "$KIT_ROOT/.role-loop"; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
# The zellij path starts adapters/<host>/role-loop.sh — the sandbox needs a host that has a loop.
sed -i '' 's/^KIT_HOST="test-fixture"/KIT_HOST="claude-code"/' "$KIT_ENV_FILE"
# A faked zellij: "action new-tab --layout <file>" starts the pane command from the layout file in the background.
cat > "$F/zellij" <<'Z'
#!/usr/bin/env bash
echo "zellij $*" >> "$ZELLIJ_LOG"
[ "${FAKE_ZELLIJ_FAIL:-0}" = 1 ] && exit 1
layout=""; while [ $# -gt 0 ]; do [ "$1" = "--layout" ] && layout="$2"; shift; done
[ -n "$layout" ] || exit 0
run="$(python3 - "$layout" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r'args "-lc" "((?:[^"\\]|\\.)*)"', t)
print(m.group(1).replace('\\"', '"').replace('\\\\', '\\'))
PY
)"
nohup bash -c "$run" >> "$ZELLIJ_LOG.pane" 2>&1 &
Z
chmod +x "$F/zellij"
# The faked host must be called "claude": host_alive of the claude-code adapter checks the process name.
# Called "sleep" it would count as dead at once and the loop would not wait — the case would not prove the waiting.
ln -sf "$(command -v sleep)" "$F/claude"
export PATH="$F:$PATH" ZELLIJ_LOG="$SANDBOX/zellij.log" ZELLIJ_SESSION_NAME="kit-eval" SHELL=/bin/bash
: > "$ZELLIJ_LOG"
"$F/claude" 300 & ALT=$!
export KIT_ROLE=engineer-a KIT_HOST_PID="$ALT" KIT_RESTART_DELAY=1 KIT_LOOP_AFTER_SECONDS=20 KIT_LOOP_SLEEP=0
unset KIT_ROLE_LOOP
# The "new session" of the loop: records that it ran, and sets the stop file.
export KIT_LOOP_CLAUDE='date +%s >> "$KIT_ROOT/.role-loop/engineer-a.started"; touch "$KIT_ROOT/.role-loop/engineer-a.stop"'
# Since the loop ticks first and starts only when there is work (case 35), engineer-a needs a free ticket —
# otherwise it waits for KIT_TICK_INTERVAL and never starts the host. What is checked here is the restart path.
sandbox_plannable 59 "src/m59/**" > /dev/null
sandbox_issue 59 '{"labels":["status:planned","sprint:current"]}'
"$BIN/brain.sh" handover "state 2026-09-15" <<<'No ticket open.' > /dev/null
errors=""
d="$(KIT_RESTART_DRY_RUN=1 "$BIN/restart-self.sh" stop 2>&1)"
case "$d" in *"zellij tab 'engineer-a (loop)'"*"role-loop.sh' 'engineer-a' --after $ALT"*) ;; *) errors="$errors dryrun:'$(echo "$d" | tr '\n' ' ' | cut -c1-160)'" ;; esac
[ ! -s "$ZELLIJ_LOG" ] || errors="$errors dryrun-called-zellij"
t0=$(date +%s)
o="$("$BIN/restart-self.sh" stop 2>&1)"; rc=$?
[ "$rc" = 0 ] || errors="$errors exit-$rc:'$o'"
grep -q "action new-tab --name engineer-a (loop) --layout" "$ZELLIJ_LOG" || errors="$errors no-new-tab"
for _ in $(seq 1 25); do kill -0 "$ALT" 2>/dev/null || break; sleep 1; done
kill -0 "$ALT" 2>/dev/null && errors="$errors old-host-alive"
for _ in $(seq 1 25); do [ -f "$KIT_ROOT/.role-loop/engineer-a.started" ] && break; sleep 1; done
[ -f "$KIT_ROOT/.role-loop/engineer-a.started" ] || errors="$errors loop-did-not-start"
L="$KIT_ROOT/.role-loop/engineer-a.log"
w="$(grep -n "waiting for host PID $ALT to end" "$L" 2>/dev/null | head -1 | cut -d: -f1)"; s="$(grep -n 'starting claude' "$L" 2>/dev/null | head -1 | cut -d: -f1)"
[ -n "$w" ] && [ -n "$s" ] && [ "$w" -lt "$s" ] || errors="$errors order(wait=$w,start=$s)"
# zellij fails: nothing is ended
rm -rf "$KIT_ROOT/.role-loop"
"$F/claude" 300 & ALT2=$!
o2="$(FAKE_ZELLIJ_FAIL=1 KIT_HOST_PID="$ALT2" "$BIN/restart-self.sh" stop 2>&1)"; rc2=$?
sleep 2
kill -0 "$ALT2" 2>/dev/null || errors="$errors zellij-error-ended-anyway"
[ "$rc2" != 0 ] || errors="$errors zellij-error-exit0"
observe "dry run: a tab with role-loop.sh engineer-a --after $ALT, zellij not called · real: the tab opened, the old host ended, the loop waited and started ($(( $(date +%s) - t0 )) s) · zellij fails: exit $rc2, the host lives${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
