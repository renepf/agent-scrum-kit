#!/usr/bin/env bash
CASE_DESC="qwen-code and pi start.sh refuse a model without tool calls, exec the host with the measured flags, pi needs its provider entry, host-alive tells the host from a reused PID"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$STUB" $SLEEPERS 2>/dev/null; sandbox_cleanup' EXIT

PORTFILE="$SANDBOX/port"
python3 "$KIT_ROOT/evals/lib/openai-stub.py" "$PORTFILE" &
STUB=$!
for _ in $(seq 1 50); do [ -s "$PORTFILE" ] && break; sleep 0.1; done
URL="http://127.0.0.1:$(cat "$PORTFILE")/v1"
echo "KIT_LOCAL_BASE_URL=\"$URL\"" >> "$SANDBOX/kit.env"
model() { sed -i.bak '/^KIT_LOCAL_MODEL=/d' "$SANDBOX/kit.env"; echo "KIT_LOCAL_MODEL=\"$1\"" >> "$SANDBOX/kit.env"; }

# Fake hosts: record PID, the kit variables and every argument, then exit.
FAKE="$SANDBOX/fakebin"; mkdir -p "$FAKE"
for h in qwen pi; do
  cat > "$FAKE/$h" <<'SH'
#!/usr/bin/env bash
{ echo "PID $$"; echo "HOST_PID ${KIT_HOST_PID:-}"; echo "SID ${KIT_SESSION_ID:-}"; echo "ROLE ${KIT_ROLE:-}"
  echo "HOST ${KIT_HOST:-}"; echo "PWD $PWD"; printf 'ARG %s\n' "$@"; } > "$CALLED_DIR/called-$(basename "$0")"
SH
  chmod +x "$FAKE/$h"
done
export CALLED_DIR="$SANDBOX" PI_CODING_AGENT_DIR="$SANDBOX/pi-agent"
start() { rm -f "$SANDBOX/called-$2"; OUT="$(PATH="$FAKE:$PATH" "$KIT_ROOT/adapters/$1/start.sh" engineer-a 2>&1)"; RC=$?; }
val() { grep "^$2 " "$SANDBOX/called-$1" 2>/dev/null | head -1 | cut -d' ' -f2-; }
args() { grep '^ARG ' "$SANDBOX/called-$1" 2>/dev/null | cut -d' ' -f2- | tr '\n' ' '; }
UUID='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
fehler=""

# --- refuse a model without tool calls, for both hosts. pi gets a valid provider entry first, so only the model
# check can refuse (without it the provider check would refuse too and hide a missing model check).
model text-only
mkdir -p "$PI_CODING_AGENT_DIR"
printf '{"providers":{"kit-local":{"baseUrl":"%s","api":"openai-completions","apiKey":"local","models":[{"id":"text-only"}]}}}' "$URL" > "$PI_CODING_AGENT_DIR/models.json"
for pair in qwen-code:qwen pi:pi; do
  start "${pair%%:*}" "${pair##*:}"
  [ "$RC" != 0 ] && [ ! -e "$SANDBOX/called-${pair##*:}" ] || fehler="$fehler ${pair%%:*}:text-only-started(exit $RC)"
done
rm -f "$PI_CODING_AGENT_DIR/models.json"

# --- qwen-code with a passing model
model tool-ok
start qwen-code qwen
sid="$(val qwen SID)"
[ "$RC" = 0 ] && [ -e "$SANDBOX/called-qwen" ] || fehler="$fehler qwen:not-started(exit $RC: $(printf '%s' "$OUT" | tail -1))"
[ -n "$(val qwen PID)" ] && [ "$(val qwen PID)" = "$(val qwen HOST_PID)" ] || fehler="$fehler qwen:no-exec(pid $(val qwen PID) host_pid $(val qwen HOST_PID))"
printf '%s' "$sid" | grep -Eq "$UUID" && [ "$sid" != "eval-session" ] || fehler="$fehler qwen:session-id='$sid'"
case "$(args qwen)" in *"--auth-type openai --model tool-ok --openai-api-key local --openai-base-url $URL --session-id $sid -i "*"roles/engineer.md"*) ;;
  *) fehler="$fehler qwen:args='$(args qwen | cut -c1-160)'" ;; esac
[ "$(val qwen ROLE)" = engineer-a ] && [ "$(val qwen HOST)" = qwen-code ] && [ "$(val qwen PWD)" = "$(cd "$SANDBOX" && pwd)" ] || fehler="$fehler qwen:env"
q_ok="$(printf '%s' "$(args qwen)" | cut -c1-60)"

# --- pi: provider entry missing, then pointing elsewhere, then right
start pi pi
[ "$RC" != 0 ] && [ ! -e "$SANDBOX/called-pi" ] || fehler="$fehler pi:started-without-provider"
case "$OUT" in *'"kit-local"'*"$URL"*) ;; *) fehler="$fehler pi:no-provider-snippet" ;; esac
mkdir -p "$PI_CODING_AGENT_DIR"
printf '{"providers":{"kit-local":{"baseUrl":"http://127.0.0.1:1/v1","api":"openai-completions","apiKey":"local","models":[{"id":"tool-ok"}]}}}' > "$PI_CODING_AGENT_DIR/models.json"
start pi pi
[ "$RC" != 0 ] && [ ! -e "$SANDBOX/called-pi" ] || fehler="$fehler pi:started-with-wrong-baseUrl"
printf '{"providers":{"kit-local":{"baseUrl":"%s","api":"openai-completions","apiKey":"local","models":[{"id":"tool-ok"}]}}}' "$URL" > "$PI_CODING_AGENT_DIR/models.json"
start pi pi
psid="$(val pi SID)"
[ "$RC" = 0 ] && [ -e "$SANDBOX/called-pi" ] || fehler="$fehler pi:not-started(exit $RC: $(printf '%s' "$OUT" | tail -1))"
[ -n "$(val pi PID)" ] && [ "$(val pi PID)" = "$(val pi HOST_PID)" ] || fehler="$fehler pi:no-exec"
printf '%s' "$psid" | grep -Eq "$UUID" && [ "$psid" != "$sid" ] || fehler="$fehler pi:session-id='$psid'"
case "$(args pi)" in "--provider kit-local --model tool-ok --session-id $psid "*"roles/engineer.md"*) ;;
  *) fehler="$fehler pi:args='$(args pi | cut -c1-160)'" ;; esac
[ "$(val pi ROLE)" = engineer-a ] && [ "$(val pi HOST)" = pi ] || fehler="$fehler pi:env"

# --- session-id.sh and host-pid.sh print the start values or fail
for h in qwen-code pi; do
  env -i PATH=/usr/bin:/bin "$KIT_ROOT/adapters/$h/session-id.sh" > /dev/null 2>&1 && fehler="$fehler $h:session-id-without-variable"
  [ "$(env -i PATH=/usr/bin:/bin KIT_SESSION_ID=s-1 "$KIT_ROOT/adapters/$h/session-id.sh" 2>/dev/null)" = s-1 ] || fehler="$fehler $h:session-id-ignores-variable"
  env -i PATH=/usr/bin:/bin "$KIT_ROOT/adapters/$h/host-pid.sh" > /dev/null 2>&1 && fehler="$fehler $h:host-pid-without-variable"
  [ "$(env -i PATH=/usr/bin:/bin KIT_HOST_PID=4242 "$KIT_ROOT/adapters/$h/host-pid.sh" 2>/dev/null)" = 4242 ] || fehler="$fehler $h:host-pid-ignores-variable"
done

# --- host-alive: the host process counts, a reused PID of something else does not
mkdir -p "$SANDBOX/alive/bin"
# The fake qwen keeps …/bin/qwen in its command line and takes its sleep along on TERM.
printf '#!/usr/bin/env bash\ntrap '\''kill $c; exit'\'' TERM\nsleep 30 & c=$!\nwait $c\n' > "$SANDBOX/alive/bin/qwen"; chmod +x "$SANDBOX/alive/bin/qwen"
ln -s /bin/sleep "$SANDBOX/alive/pi"   # a copy of a system binary is killed by macOS; a symlink runs as …/pi
"$SANDBOX/alive/bin/qwen" --auth-type openai > /dev/null 2>&1 & QP=$!
"$SANDBOX/alive/pi" 30 > /dev/null 2>&1 & PP=$!
# No background process may hold the pipe of evals/run.sh.
sleep 30 > /dev/null 2>&1 & OP=$!
SLEEPERS="$QP $PP $OP"
sleep 0.3
"$KIT_ROOT/adapters/qwen-code/host-alive.sh" "$QP" || fehler="$fehler qwen:alive-host-not-seen"
"$KIT_ROOT/adapters/qwen-code/host-alive.sh" "$OP" && fehler="$fehler qwen:other-process-counts"
"$KIT_ROOT/adapters/pi/host-alive.sh" "$PP" || fehler="$fehler pi:alive-host-not-seen"
"$KIT_ROOT/adapters/pi/host-alive.sh" "$OP" && fehler="$fehler pi:other-process-counts"
kill $SLEEPERS 2>/dev/null; wait $SLEEPERS 2>/dev/null
"$KIT_ROOT/adapters/pi/host-alive.sh" "$PP" && fehler="$fehler pi:dead-pid-counts"

observe "text-only refused by both · qwen exec pid=host_pid, args '${q_ok}…' · pi without/wrong provider refused, then started · session-id/host-pid from start values · host-alive host yes, other no${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
