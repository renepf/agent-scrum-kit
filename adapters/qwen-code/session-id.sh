#!/usr/bin/env bash
# Prints the session id or fails. Never guesses.
# adapters/qwen-code/start.sh passes KIT_SESSION_ID as --session-id and exports it. Measured: qwen names its chat
# file and its registry record after that id. NOT measured: that a shell tool inside qwen sees the exported
# variable (no local model on the build machine produced a tool call), and whether a context reset in qwen keeps
# the id. The registry $QWEN_HOME/sessions/<pid>.json names the id too, but under the grandchild of the start
# process, not under KIT_HOST_PID; it is not read here.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "no session id: start the session with adapters/qwen-code/start.sh, or set KIT_SESSION_ID — not guessed" >&2
exit 1
