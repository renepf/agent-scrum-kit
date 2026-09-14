#!/usr/bin/env bash
# Druckt die Session-Kennung oder scheitert. Nie raten.
#
# Reihenfolge, beide gemessen:
#   1. Registry des eigenen claude-Prozesses: ~/.claude/sessions/<host-pid>.json, Feld sessionId.
#      /clear laesst den Prozess stehen, vergibt aber eine neue Session-ID — die Registry bekommt
#      sie nachweislich (Referenz-Loop, 2026-09-10: PID 6568 → neue Session ab 17:31).
#   2. CLAUDE_CODE_SESSION_ID. Ob diese Variable nach /clear erneuert wird, ist NICHT gemessen —
#      deshalb nur Rueckfall.
# NICHT aus der juengsten Transkriptdatei ableiten: bei neun parallelen Sessions gehoert sie der
# Session, die zuletzt geschrieben hat.
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
echo "keine Session-ID: weder Registry ~/.claude/sessions/<pid>.json noch CLAUDE_CODE_SESSION_ID — nicht raten" >&2
exit 1
