#!/usr/bin/env bash
# Exit 0, wenn unter <pid> ein claude-Prozess lebt. Eine lebende PID eines ANDEREN Prozesses zaehlt nicht.
set -euo pipefail
[ $# -ge 1 ] || exit 2
comm="$(ps -o comm= -p "$1" 2>/dev/null)" || exit 1
[ "$(basename "$comm")" = "claude" ]
