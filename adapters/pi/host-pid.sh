#!/usr/bin/env bash
# Prints the PID of the pi process, or fails. adapters/pi/start.sh exports it as KIT_HOST_PID before exec.
# Measured 2026-09-15: a pi session is one process named "pi"; nothing is left after SIGTERM to it.
[ -n "${KIT_HOST_PID:-}" ] && echo "$KIT_HOST_PID" && exit 0
exit 1
