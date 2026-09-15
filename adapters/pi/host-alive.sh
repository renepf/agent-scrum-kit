#!/usr/bin/env bash
# Exit 0 only if a process named "pi" lives under <pid> (measured 2026-09-15). A reused PID does not count.
set -euo pipefail
[ $# -ge 1 ] || exit 2
comm="$(ps -o comm= -p "$1" 2>/dev/null)" || exit 1
[ "$(basename "$comm")" = "pi" ]
