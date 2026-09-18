#!/usr/bin/env bash
# Prints the PID of the claude process this call runs under, or fails.
# The chain is: script -> shell of the tool call -> claude (measured 2026-09-10).
# The PID stays the same across every tool call of a session; two instances have two.
set -euo pipefail
p=$$
for _ in 1 2 3 4 5 6 7 8 9 10; do
  line="$(ps -o ppid=,comm= -p "$p" 2>/dev/null)" || exit 1
  comm="$(echo "$line" | awk '{ $1=""; sub(/^ /,""); print }')"
  case "$(basename "$comm")" in claude) echo "$p"; exit 0 ;; esac
  p="$(echo "$line" | awk '{print $1}')"
  [ "$p" -gt 1 ] || exit 1
done
exit 1
