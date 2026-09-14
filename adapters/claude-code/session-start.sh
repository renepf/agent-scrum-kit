#!/usr/bin/env bash
# SessionStart-Hook fuer claude-code. Gibt einer Kit-Rolle nach Start, /clear oder resume ihren
# Auftrag zurueck. Ohne Rolle (kein KIT_ROLE, kein Anker) gibt er nichts aus — fremde Sessions
# merken nichts.
#
#   session-start.sh          Kontext-Modus: JSON mit additionalContext auf stdout
#   session-start.sh --wake   Weck-Modus fuer einen zweiten Hook-Eintrag mit asyncRewake:
#                             bei startup|clear|resume Text auf stderr und exit 2 — das weckt die
#                             Session und macht den Text zum naechsten Turn, ohne Eingabe.
#                             Bei compact und fork still (Referenz-Messung 2026-09-11: fork
#                             feuerte zusaetzlich und haette doppelt geweckt).
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT="$(cat 2>/dev/null || true)"
SOURCE="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("source","?"))
except Exception: print("?")' 2>/dev/null)"

R="${KIT_ROLE:-}"
if [ -z "$R" ]; then
  HP="${KIT_HOST_PID:-$("$KIT_ROOT/adapters/claude-code/host-pid.sh" 2>/dev/null || true)}"
  [ -n "$HP" ] && [ -f "$KIT_ROOT/.pid-roles/$HP" ] && R="$(cat "$KIT_ROOT/.pid-roles/$HP")"
fi
[ -n "$R" ] || exit 0

case "$R" in engineer-a|engineer-b) FILE=engineer.md ;; *) FILE="$R.md" ;; esac
[ -f "$KIT_ROOT/roles/$FILE" ] || exit 0
case "$R" in product-owner|acceptance-tester|merge-gate) IV=10m ;; *) IV=5m ;; esac
EXTRA=""; [ "$R" = "watchdog" ] && EXTRA=" Danach bin/budget.sh, vier Blicke, bin/commit.sh."

CTX="AGENT-SCRUM-KIT — ROLLENANKER (SessionStart: $SOURCE)
Du bist die Rolle **$R**. Das gilt auch nach /clear: dein Kontext ist neu, deine Rolle nicht.

Sofort, in dieser Reihenfolge:
1. Lies roles/_COMMON.md und roles/$FILE.
2. Fuehre bin/tick.sh aus. Er erkennt die neue Session, registriert dich neu und zeigt deine letzte Uebergabe.
3. Setze an der letzten Uebergabe fort.
4. Pruefe, ob dein Loop laeuft (CronList). Wenn nicht:
   /loop $IV Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite deine Rolle laut roles/$FILE: ein Ticket zur Zeit, aufgreifen heisst sofort den In-Status setzen, kein Subagent.$EXTRA

Die Skripte kennen deine Rolle auch ohne KIT_ROLE ueber den Anker in .pid-roles/."

if [ "${1:-}" = "--wake" ]; then
  case "$SOURCE" in startup|clear|resume) ;; *) exit 0 ;; esac
  sleep "${KIT_WAKE_DELAY:-2}"
  printf '%s\n' "$CTX" >&2
  exit 2
fi

python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$CTX"
