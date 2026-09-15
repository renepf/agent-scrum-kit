#!/usr/bin/env bash
CASE_DESC="qwen-code and pi on the configured local model run a shell tool that sees KIT_SESSION_ID, and transcript-path.sh finds both transcripts"
CASE_KIND="live"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT

# Endpoint and model come from the real kit.env; without them, or when the model fails the check, the run is
# BLOCKED (no verdict about the adapters). Each host gets its own config dir in the sandbox.
REAL="$KIT_ROOT/kit.env"
url="$(grep -m1 '^KIT_LOCAL_BASE_URL=' "$REAL" 2>/dev/null | cut -d= -f2- | tr -d '"')"
mdl="$(grep -m1 '^KIT_LOCAL_MODEL=' "$REAL" 2>/dev/null | cut -d= -f2- | tr -d '"')"
if [ -z "$url" ] || [ -z "$mdl" ]; then
  echo "BEOBACHTET: BLOCKIERT — KIT_LOCAL_BASE_URL or KIT_LOCAL_MODEL not set in kit.env"; exit 3
fi
printf 'KIT_LOCAL_BASE_URL="%s"\nKIT_LOCAL_MODEL="%s"\n' "$url" "$mdl" >> "$SANDBOX/kit.env"
if ! chk="$("$BIN/local-model-check.sh" 2>&1)"; then
  echo "BEOBACHTET: BLOCKIERT — $(printf '%s' "$chk" | tail -1)"; exit 3
fi

mkdir -p "$SANDBOX/proj" "$SANDBOX/qwen-home" "$SANDBOX/pi-agent"
printf '{"providers":{"kit-local":{"baseUrl":"%s","api":"openai-completions","apiKey":"local","models":[{"id":"%s"}]}}}' \
  "$url" "$mdl" > "$SANDBOX/pi-agent/models.json"
NODEBIN="$(dirname "$(command -v qwen || command -v pi || echo /usr/bin/false)")"
new_id() { python3 -c 'import uuid; print(uuid.uuid4())'; }
ask() { echo "Run this shell command exactly once, then answer done: sh -c 'printf %s \"\$KIT_SESSION_ID\" > $SANDBOX/proj/seen-$1'"; }
fehler=""

qid="$(new_id)"
( cd "$SANDBOX/proj" && env -i HOME="$HOME" PATH="$NODEBIN:/usr/bin:/bin" TERM=dumb QWEN_HOME="$SANDBOX/qwen-home" \
    KIT_SESSION_ID="$qid" qwen --max-wall-time 15m --auth-type openai --model "$mdl" --openai-api-key local \
    --openai-base-url "$url" --session-id "$qid" --approval-mode yolo "$(ask qwen)" < /dev/null > "$SANDBOX/qwen.out" 2>&1 )
qrc=$?
pid_="$(new_id)"
( cd "$SANDBOX/proj" && env -i HOME="$HOME" PATH="$NODEBIN:/usr/bin:/bin" TERM=dumb PI_CODING_AGENT_DIR="$SANDBOX/pi-agent" \
    PI_OFFLINE=1 KIT_SESSION_ID="$pid_" pi --provider kit-local --model "$mdl" --session-id "$pid_" \
    -p "$(ask pi)" < /dev/null > "$SANDBOX/pi.out" 2>&1 ) &
PI_RUN=$!   # macOS has no timeout(1): stop pi after 900 s
( sleep 900; kill "$PI_RUN" 2>/dev/null ) & WATCH=$!
wait "$PI_RUN"
prc=$?
kill "$WATCH" 2>/dev/null

[ "$(cat "$SANDBOX/proj/seen-qwen" 2>/dev/null)" = "$qid" ] || fehler="$fehler qwen:tool-shell-saw='$(cat "$SANDBOX/proj/seen-qwen" 2>/dev/null)'(exit $qrc)"
[ "$(cat "$SANDBOX/proj/seen-pi" 2>/dev/null)" = "$pid_" ] || fehler="$fehler pi:tool-shell-saw='$(cat "$SANDBOX/proj/seen-pi" 2>/dev/null)'(exit $prc)"
QWEN_HOME="$SANDBOX/qwen-home" "$KIT_ROOT/adapters/qwen-code/transcript-path.sh" "$qid" > /dev/null 2>&1 || fehler="$fehler qwen:no-transcript"
PI_CODING_AGENT_DIR="$SANDBOX/pi-agent" "$KIT_ROOT/adapters/pi/transcript-path.sh" "$pid_" > /dev/null 2>&1 || fehler="$fehler pi:no-transcript"

observe "model $mdl · qwen exit $qrc, tool shell saw its id: $([ -e "$SANDBOX/proj/seen-qwen" ] && echo yes || echo no) · pi exit $prc, tool shell saw its id: $([ -e "$SANDBOX/proj/seen-pi" ] && echo yes || echo no)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
