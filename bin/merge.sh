#!/usr/bin/env bash
# Ticket mergen und auf done setzen — nur wenn alle Bedingungen fuer den AKTUELLEN PR-HEAD stehen.
#
#   bin/merge.sh 795
#
# product-owner: braucht 'MERGE-GATE OK — HEAD `<sha8>`' im PR und gruene CI.
# merge-gate:    braucht zusaetzlich 'PO OK — HEAD `<sha8>`'. Der product-owner hat das letzte Wort.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ $# -ge 1 ] || die "Aufruf: bin/merge.sh <ticket>"
TICKET="$1"; R="$(role)"
case "$R" in product-owner|merge-gate) ;; *) die "mergen darf nur der product-owner, oder merge-gate mit PO OK — nicht $R" ;; esac
"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden"

NEED=("MERGE-GATE OK")
[ "$R" = "merge-gate" ] && NEED+=("PO OK")
verdicts_missing "$TICKET" "${NEED[@]}"
[ -z "$VERDICT_MISSING" ] || die "#$TICKET: Merge abgelehnt — im PR #$VERDICT_PR fehlt fuer HEAD $VERDICT_HEAD8:$VERDICT_MISSING"
# Ein aufgegebenes AC faellt nie still weg: solange ein ABANDON steht, kein Merge.
HANDOFF="$(python3 "$BIN_DIR/gates.py" abandoned "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" || die "#$TICKET: Merge abgelehnt — $HANDOFF"
# Jedes Gate fuer diesen HEAD: ausfuehrbare gruen gelaufen, manuelle belegt.
GATE_MSG="$(python3 "$BIN_DIR/gates.py" unmet "$TICKETS_DIR/$TICKET/GATES.md" "$VERDICT_HEAD8" all 2>&1)" \
  || die "#$TICKET: Merge abgelehnt — $GATE_MSG"

# CI frisch messen. Nur Exit 0 heisst gruen; laufend oder rot ist kein Ergebnis.
set +e; CHECKS="$("$BIN_DIR/tickets.sh" pr-checks "$VERDICT_PR" 2>&1)"; RC=$?; set -e
[ "$RC" -eq 0 ] || die "#$TICKET: Merge abgelehnt — CI von PR #$VERDICT_PR nicht gruen (exit $RC): $CHECKS"

"$BIN_DIR/tickets.sh" pr-merge "$VERDICT_PR"
STATE="$("$BIN_DIR/tickets.sh" pr-state "$VERDICT_PR")"
case "$STATE" in MERGED*) ;; *) die "PR #$VERDICT_PR nach dem Merge nicht MERGED, sondern '$STATE' — nicht auf done setzen" ;; esac

"$BIN_DIR/status.sh" "$TICKET" done "PR #$VERDICT_PR gemergt als ${STATE#MERGED } (HEAD $VERDICT_HEAD8) durch $R"
echo "Branch-Cleanup getrennt pruefen — ein Merge-Aufruf mit exit 0 sagt nichts ueber den geloeschten Branch."
