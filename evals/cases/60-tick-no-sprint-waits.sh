#!/usr/bin/env bash
CASE_DESC="tick ohne aktiven Sprint: wartet mit Exit 0, schreibt nichts"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
out="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"; rc=$?
dateien="$(find "$SANDBOX/sprints" -type f | wc -l | tr -d ' ')"
observe "Exit $rc · Ausgabe: $out · Dateien unter sprints/: $dateien"
echo "BEOBACHTET: $OBSERVED"
[ "$rc" = 0 ] && [ "$dateien" = 0 ] && case "$out" in *"kein aktiver Sprint"*) true ;; *) false ;; esac
