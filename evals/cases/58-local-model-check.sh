#!/usr/bin/env bash
CASE_DESC="local-model-check measures a structured tool call per model; text that looks like a call is no, a failed request is UNKNOWN, only the configured model passing exits 0"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$STUB" 2>/dev/null; sandbox_cleanup' EXIT

# Stub endpoint: evals/lib/openai-stub.py (tool-ok, text-only as measured on Ollama, broken).
PORTFILE="$SANDBOX/port"
python3 "$KIT_ROOT/evals/lib/openai-stub.py" "$PORTFILE" &
STUB=$!
for _ in $(seq 1 50); do [ -s "$PORTFILE" ] && break; sleep 0.1; done
PORT="$(cat "$PORTFILE")"
echo "KIT_LOCAL_BASE_URL=\"http://127.0.0.1:$PORT/v1\"" >> "$SANDBOX/kit.env"

check() { # $1 = KIT_LOCAL_MODEL line for kit.env ('' = none)
  sed -i.bak '/^KIT_LOCAL_MODEL=/d' "$SANDBOX/kit.env"
  [ -z "$1" ] || echo "KIT_LOCAL_MODEL=\"$1\"" >> "$SANDBOX/kit.env"
  OUT="$("$BIN/local-model-check.sh" 2>&1)"; RC=$?
}
row() { printf '%s\n' "$OUT" | grep -E "^  $1 " | head -1; }

errors=""
check tool-ok
case "$(row tool-ok)" in *"tool calls: yes"*) ;; *) errors="$errors tool-ok-row='$(row tool-ok)'" ;; esac
case "$(row text-only)" in *"tool calls: no"*) ;; *) errors="$errors text-only-row='$(row text-only)'" ;; esac
case "$(row broken)" in *"tool calls: UNKNOWN"*500*) ;; *) errors="$errors broken-row='$(row broken)'" ;; esac
[ "$RC" = 0 ] || errors="$errors configured-pass-exit=$RC"
rc_ok=$RC

check text-only; rc_text=$RC
[ "$rc_text" != 0 ] || errors="$errors configured-text-only-exit-0"
case "$OUT" in *"text-only"*"refused"*) ;; *) errors="$errors text-only-not-refused" ;; esac

check broken; rc_broken=$RC
[ "$rc_broken" != 0 ] || errors="$errors configured-broken-exit-0"

check ""; rc_none=$RC
[ "$rc_none" != 0 ] || errors="$errors no-model-exit-0"
case "$OUT" in *"KIT_LOCAL_MODEL is not set"*) ;; *) errors="$errors no-model-message-missing" ;; esac

kill "$STUB" 2>/dev/null; wait "$STUB" 2>/dev/null
check tool-ok; rc_down=$RC
[ "$rc_down" != 0 ] || errors="$errors endpoint-down-exit-0"
case "$OUT" in *UNKNOWN*) ;; *) errors="$errors endpoint-down-not-UNKNOWN" ;; esac

observe "exit: tool-ok $rc_ok · text-only $rc_text · broken $rc_broken · none $rc_none · endpoint down $rc_down${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
