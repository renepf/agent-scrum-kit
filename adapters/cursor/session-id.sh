#!/usr/bin/env bash
# UNKNOWN — where the cursor-agent chatId is stored is not measured (see README).
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "UNKNOWN — the session id for cursor cannot be determined. Set KIT_SESSION_ID by hand. To check under ~/.cursor/" >&2
exit 1
