#!/usr/bin/env bash
# UNKNOWN — Sessionkennung fuer codex nicht geprueft (siehe README).
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "UNKNOWN — Sessionkennung fuer codex nicht ermittelbar. KIT_SESSION_ID von Hand setzen." >&2
exit 1
