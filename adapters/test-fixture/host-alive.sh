#!/usr/bin/env bash
# Evals: KIT_HOST_ALIVE_NAME decides which process name counts as a host (default: any living process).
set -euo pipefail
comm="$(ps -o comm= -p "$1" 2>/dev/null)" || exit 1
[ -z "${KIT_HOST_ALIVE_NAME:-}" ] || [ "$(basename "$comm")" = "$KIT_HOST_ALIVE_NAME" ]
