#!/usr/bin/env bash
CASE_DESC="ungeklaerte Adapter tragen UNKNOWN und keinen erfundenen Startbefehl"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

SATZ="UNKNOWN — Startbefehl, Sessionkennung und Werkzeugnamen beim Owner erfragen"
fehler=""
for host in hermes; do
  R="$KIT_ROOT/adapters/$host/README.md"
  [ -f "$R" ] || { fehler="$fehler $host:kein-README"; continue; }
  n="$(grep -c "$SATZ" "$R" || true)"
  [ "$n" -ge 3 ] || fehler="$fehler $host:UNKNOWN-Satz nur ${n}x"
  # Ein Codeblock mit einem Startbefehl waere eine Erfindung.
  if grep -qE '^\s*(\$ )?[a-z][a-z0-9-]+ +(--?[a-z]|run|start|chat)' "$R"; then
    fehler="$fehler $host:sieht-nach-erfundenem-Befehl-aus"
  fi
  # Die Skripte duerfen scheitern, aber nie etwas erfinden.
  "$KIT_ROOT/adapters/$host/session-id.sh" > /dev/null 2>&1 && fehler="$fehler $host:session-id.sh-liefert-etwas"
done

observe "hermes: UNKNOWN-Satz vorhanden, kein Startbefehl, session-id.sh scheitert${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
