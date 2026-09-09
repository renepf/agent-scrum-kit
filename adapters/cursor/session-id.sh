#!/usr/bin/env bash
# UNKNOWN — Ablageort der cursor-agent chatId nicht geprueft (siehe README).
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "UNKNOWN — Session-Kennung fuer cursor nicht ermittelbar. KIT_SESSION_ID von Hand setzen. Zu pruefen unter ~/.cursor/" >&2
exit 1
