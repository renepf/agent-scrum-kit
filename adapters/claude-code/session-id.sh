#!/usr/bin/env bash
# Druckt die Session-Kennung oder scheitert. Nie raten.
#
# Claude Code setzt CLAUDE_CODE_SESSION_ID in jeder Session. Der Wert ist der Dateiname des
# Transkripts unter ~/.claude/projects/<slug>/<kennung>.jsonl (gemessen 2026-09-10).
#
# NICHT aus der juengsten Transkriptdatei ableiten: bei parallelen Sessions ist die juengste
# Datei die der Session, die zuletzt geschrieben hat — nicht die eigene. Der Watchdog wuerde
# dann den Kontextstand einer fremden Rolle messen.
set -euo pipefail
if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; exit 0; fi
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then echo "$CLAUDE_CODE_SESSION_ID"; exit 0; fi
echo "keine Session-Kennung: weder KIT_SESSION_ID noch CLAUDE_CODE_SESSION_ID gesetzt. Nicht raten." >&2
exit 1
