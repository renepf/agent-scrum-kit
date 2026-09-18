#!/usr/bin/env bash
# UNKNOWN — ask the owner for the start command, the session id and the tool names.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "UNKNOWN — ask the owner for the session id for hermes. Set KIT_SESSION_ID by hand." >&2
exit 1
