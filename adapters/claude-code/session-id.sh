#!/usr/bin/env bash
# Prints the session id or fails. Never guess.
#
# The order, both measured:
#   1. the registry of your own claude process: ~/.claude/sessions/<host-pid>.json, field sessionId.
#      /clear leaves the process standing but hands out a new session id — the registry demonstrably
#      gets it (reference loop, 2026-09-10: PID 6568 → a new session from 17:31).
#   2. CLAUDE_CODE_SESSION_ID. Whether this variable is renewed after /clear is NOT measured —
#      hence only a fallback.
# Do NOT derive it from the youngest transcript file: with nine parallel sessions that one belongs to
# the session that wrote last.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hp="${KIT_HOST_PID:-$("$HERE/host-pid.sh" 2>/dev/null || true)}"
reg="${KIT_CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}/$hp.json"
if [ -n "$hp" ] && [ -f "$reg" ]; then
  sid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("sessionId",""))' "$reg" 2>/dev/null || true)"
  [ -n "$sid" ] && { echo "$sid"; exit 0; }
fi
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then echo "$CLAUDE_CODE_SESSION_ID"; exit 0; fi
echo "no session id: neither the registry ~/.claude/sessions/<pid>.json nor CLAUDE_CODE_SESSION_ID — do not guess" >&2
exit 1
