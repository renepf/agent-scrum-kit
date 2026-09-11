#!/usr/bin/env bash
# Druckt die Session-Kennung oder scheitert. Nie raten.
#
# Claude Code setzt CLAUDE_CODE_SESSION_ID in jeder Session; der Wert ist der Dateiname des
# Transkripts unter ~/.claude/projects/<slug>/<kennung>.jsonl (gemessen 2026-09-10).
# NICHT aus der juengsten Transkriptdatei ableiten: laufen neun Sessions parallel, gehoert die
# juengste Datei der Session, die zuletzt geschrieben hat — nicht der eigenen.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then echo "$CLAUDE_CODE_SESSION_ID"; exit 0; fi
echo "weder KIT_SESSION_ID noch CLAUDE_CODE_SESSION_ID gesetzt — nicht raten" >&2
exit 1
