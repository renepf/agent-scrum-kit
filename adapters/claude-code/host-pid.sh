#!/usr/bin/env bash
# Druckt die PID des claude-Prozesses, unter dem dieser Aufruf laeuft, oder scheitert.
# Die Kette ist: Skript -> Shell des Werkzeugaufrufs -> claude (gemessen 2026-09-10).
# Die PID bleibt ueber alle Werkzeugaufrufe einer Session gleich; zwei Instanzen haben zwei.
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
