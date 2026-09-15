#!/usr/bin/env bash
# Prints the transcript path of one session id, one per line, or fails. Never the newest file.
# Measured 2026-09-15 (qwen 0.23.4, env -i): $QWEN_HOME/projects/<cwd with / as ->/chats/<session-id>.jsonl,
# QWEN_HOME defaults to ~/.qwen. QWEN_RUNTIME_DIR is documented to move conversations; not measured, not read here.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: transcript-path.sh <session-id>" >&2; exit 2; }
found=0
for p in "${QWEN_HOME:-$HOME/.qwen}"/projects/*/chats/"$1".jsonl; do
  [ -e "$p" ] || continue
  echo "$p"; found=1
done
[ "$found" = 1 ] || exit 1
