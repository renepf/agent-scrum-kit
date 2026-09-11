#!/usr/bin/env bash
# Evals setzen KIT_HOST_PID selbst.
[ -n "${KIT_HOST_PID:-}" ] && echo "$KIT_HOST_PID" && exit 0
exit 1
