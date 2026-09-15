#!/usr/bin/env bash
# Prints the PID of the qwen start process, or fails. adapters/qwen-code/start.sh exports it as KIT_HOST_PID
# before exec. Measured 2026-09-15: a session is three node processes (start process, its child, grandchild);
# all three are named "node", so the process chain alone cannot tell qwen from any other node process.
[ -n "${KIT_HOST_PID:-}" ] && echo "$KIT_HOST_PID"
