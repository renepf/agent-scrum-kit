#!/usr/bin/env bash
# Druckt die Session-Kennung oder scheitert. Nie raten.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
newest="$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -1 || true)"
[ -n "$newest" ] || { echo "keine Transkriptdatei unter ~/.claude/projects/ gefunden — KIT_SESSION_ID von Hand setzen" >&2; exit 1; }
basename "$newest" .jsonl
