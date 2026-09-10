#!/usr/bin/env bash
CASE_DESC="ohne Sprint meldet der Tick Warten und endet mit Exit 0"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT

out="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"; rc=$?
fehler=""
[ "$rc" = 0 ] || fehler="$fehler exit=$rc"
case "$out" in *"kein aktiver Sprint"*) ;; *) fehler="$fehler keine-Wartemeldung" ;; esac
[ ! -e "$SANDBOX/sprints/CURRENT" ] || fehler="$fehler hat-Sprint-angelegt"

observe "Exit $rc · Ausgabe: $(echo "$out" | head -1 | cut -c1-80)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
