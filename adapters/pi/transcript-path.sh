#!/usr/bin/env bash
# Prints the session file of one session id, one per line, or fails. Never the newest file.
# Measured 2026-09-15 (pi 0.85.1, env -i): $PI_CODING_AGENT_DIR/sessions/--<cwd with / as ->--/<timestamp>_<session-id>.jsonl,
# PI_CODING_AGENT_DIR defaults to ~/.pi/agent. PI_CODING_AGENT_SESSION_DIR and --session-dir are documented; not measured, not read here.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: transcript-path.sh <session-id>" >&2; exit 2; }
found=0
for p in "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"/sessions/*/*_"$1".jsonl; do
  [ -e "$p" ] || continue
  echo "$p"; found=1
done
[ "$found" = 1 ] || exit 1
