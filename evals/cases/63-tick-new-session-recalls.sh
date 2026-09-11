#!/usr/bin/env bash
CASE_DESC="neue Session-ID im tick holt das Gedaechtnis mit der letzten Uebergabe zurueck, eine bekannte nicht"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
KIT_ROLE=engineer-a KIT_SESSION_ID=alt "$BIN/brain.sh" handover "Stand vor Reset: #12 rfr, SHA 1a2b3c4d" <<'EOF' > /dev/null
Naechster Schritt: Rueckweisung von qa-ruthless abwarten.
EOF
neu="$(KIT_ROLE=engineer-a KIT_SESSION_ID=neu "$BIN/tick.sh" 2>&1)"
wieder="$(KIT_ROLE=engineer-a KIT_SESSION_ID=neu "$BIN/tick.sh" 2>&1)"
fehler=""
printf '%s' "$neu" | grep -q 'SHA 1a2b3c4d' || fehler="$fehler Uebergabe-nicht-gezeigt"
printf '%s' "$neu" | grep -q 'Rueckweisung von qa-ruthless abwarten' || fehler="$fehler Rumpf-nicht-gezeigt"
printf '%s' "$wieder" | grep -q 'letzte Uebergabe' && fehler="$fehler recall-bei-jeder-Runde"
observe "neue Session: Uebergabe gezeigt · zweiter Tick derselben Session: kein recall${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
