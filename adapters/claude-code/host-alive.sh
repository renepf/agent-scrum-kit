#!/usr/bin/env bash
# Exit 0 when a claude process lives under <pid>. A living PID of ANOTHER process does not count.
set -euo pipefail
[ $# -ge 1 ] || exit 2
comm="$(ps -o comm= -p "$1" 2>/dev/null)" || exit 1
[ "$(basename "$comm")" = "claude" ]
