#!/usr/bin/env bash
# Prints the session id or fails. Never guesses.
# adapters/pi/start.sh passes KIT_SESSION_ID as --session-id and exports it. Measured: pi names its session file
# <timestamp>_<id>.jsonl after that id. NOT measured: that pi's bash tool sees the exported variable (no local model
# on the build machine produced a tool call), and the id after /new. pi documents PI_SESSION_ID in its tool
# environment; not measured, not read here.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "no session id: start the session with adapters/pi/start.sh, or set KIT_SESSION_ID — not guessed" >&2
exit 1
