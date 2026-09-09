#!/usr/bin/env bash
# UNKNOWN — Startbefehl, Sessionkennung und Werkzeugnamen beim Owner erfragen.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
echo "UNKNOWN — Sessionkennung fuer pi beim Owner erfragen. KIT_SESSION_ID von Hand setzen." >&2
exit 1
