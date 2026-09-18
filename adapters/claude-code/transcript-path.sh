#!/usr/bin/env bash
# Prints the transcript paths for a session id, one per line.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: transcript-path.sh <session-id>" >&2; exit 2; }
found=0
for p in "$HOME"/.claude/projects/*/"$1".jsonl; do
  [ -e "$p" ] || continue
  echo "$p"; found=1
done
[ "$found" = 1 ] || exit 1
