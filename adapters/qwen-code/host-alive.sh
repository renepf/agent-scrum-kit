#!/usr/bin/env bash
# Exit 0 only if <pid> is a qwen start process. Its name is "node" (measured 2026-09-15), so the check reads the
# command line: "node …/bin/qwen --auth-type …". A reused PID of another node process does not count.
set -euo pipefail
[ $# -ge 1 ] || exit 2
args="$(ps -o args= -p "$1" 2>/dev/null)" || exit 1
case " $args " in *"/bin/qwen "*) exit 0 ;; *) exit 1 ;; esac
