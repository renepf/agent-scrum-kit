#!/usr/bin/env bash
CASE_DESC="die Rolle ueberlebt einen Kontext-Reset ueber den Anker am Host-Prozess, ohne KIT_ROLE"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'rm -rf "$KIT_ROOT/.pid-roles/$KIT_HOST_PID"; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
fehler=""
# Ein Tick mit Rolle setzt den Anker.
KIT_ROLE=qa-ruthless "$BIN/tick.sh" > /dev/null 2>&1 || fehler="$fehler erster-tick"
anker="$(cat "$KIT_ROOT/.pid-roles/$KIT_HOST_PID" 2>/dev/null)"
[ "$anker" = "qa-ruthless" ] || fehler="$fehler anker='$anker'"
# "Reset": neue Session-ID, KIT_ROLE nicht mehr gesetzt, derselbe Host-Prozess.
out="$(env -u KIT_ROLE KIT_SESSION_ID=nach-reset "$BIN/tick.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] || fehler="$fehler tick-ohne-KIT_ROLE-exit-$rc"
grep -q '| qa-ruthless | nach-reset |' "$SANDBOX/sprints/S-001-eval/roster.md" || fehler="$fehler neue-Session-nicht-als-qa-ruthless-registriert"
# Fremder Host-Prozess ohne Anker: keine geratene Rolle.
out2="$(env -u KIT_ROLE KIT_HOST_PID=999999 "$BIN/tick.sh" 2>&1)"; rc2=$?
[ "$rc2" != 0 ] || fehler="$fehler fremder-Prozess-bekam-Rolle"
case "$out2" in *"Rolle unbekannt"*) ;; *) fehler="$fehler keine-klare-Meldung" ;; esac
observe "Anker nach Tick: $anker · ohne KIT_ROLE neu registriert als qa-ruthless: $(grep -c '| qa-ruthless | nach-reset |' "$SANDBOX/sprints/S-001-eval/roster.md") · fremder Prozess: Exit $rc2, 'Rolle unbekannt'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
