#!/usr/bin/env bash
CASE_DESC="ein Sprint ohne Chat-Eintraege ergibt einen gueltigen, leeren Index — kein stiller Abbruch"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
sandbox_ticket 1 planned
KIT_ROLE=product-owner "$BIN/tickets.sh" add-label 1 sprint:current > /dev/null

KIT_ROLE=engineer-a "$BIN/reindex.sh" > /dev/null 2>&1; rc_idx=$?
rm -f "$SPRINT/INDEX.md"
# Der ERSTE Tick eines frischen Sprints muss bis zur Warteschlange durchlaufen.
out="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"; rc_tick=$?

fehler=""
[ "$rc_idx" = 0 ] || fehler="$fehler reindex-exit=$rc_idx"
[ "$rc_tick" = 0 ] || fehler="$fehler tick-exit=$rc_tick"
case "$out" in *"deine Warteschlange"*"#1"*) ;; *) fehler="$fehler erster-Tick-endet-vor-der-Warteschlange" ;; esac

observe "reindex auf leerem Sprint: Exit $rc_idx · erster Tick: Exit $rc_tick, zeigt Warteschlange: $(case "$out" in *"#1"*) echo ja;; *) echo NEIN;; esac)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
