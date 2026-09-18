#!/usr/bin/env bash
# UNKNOWN — the session id for codex is not measured (see README).
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "UNKNOWN — the session id for codex cannot be determined. Set KIT_SESSION_ID by hand." >&2
exit 1
