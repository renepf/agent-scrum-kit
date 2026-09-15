#!/usr/bin/env bash
# Gates eines Tickets laufen lassen oder ein manuelles Gate belegen. Format: bin/gates.py.
#
#   bin/gates.sh run <nr>                        im Arbeitsbaum des PR, auf dessen HEAD
#   bin/gates.sh attest <nr> <gate> "<beleg>"    manuelles Gate belegen: acceptance-tester, product-owner
#
# Jeder Beleg haengt am HEAD des verknuepften PR und an der Definition des Gates. Ein Push oder eine
# geaenderte CHECK-, EXPECT- oder CWD-Zeile macht ihn ungueltig. CHECK ist Shell-Code aus dem Ledger
# und laeuft mit den Rechten dieser Session.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
CMD="${1:-}"; TICKET="${2:-}"
[ -n "$CMD" ] && [ -n "$TICKET" ] || die "Aufruf: bin/gates.sh run <nr> | attest <nr> <gate> \"<beleg>\""
R="$(role)"
LEDGER="$TICKETS_DIR/$TICKET/GATES.md"
[ -f "$LEDGER" ] || die "#$TICKET: kein Ledger unter $LEDGER"
PR_LINE="$("$BIN_DIR/tickets.sh" pr "$TICKET" 2>&1)" || die "#$TICKET: kein verknuepfter PR lesbar${PR_LINE:+: $PR_LINE}"
HEAD8="${PR_LINE##* }"

case "$CMD" in
  run)
    HERE="$(git rev-parse HEAD 2>/dev/null)" || die "$(pwd) ist kein Git-Arbeitsbaum — Gates laufen im Arbeitsbaum des PR"
    [ "${HERE:0:8}" = "$HEAD8" ] || die "#$TICKET: Arbeitsbaum steht auf ${HERE:0:8}, der PR auf $HEAD8 — erst den HEAD des PR auschecken"
    with_lock "$TICKETS_DIR/$TICKET/.gates.lock" \
      python3 "$BIN_DIR/gates.py" run "$LEDGER" "$HEAD8" "$(pwd)" "$R" "${KIT_GATE_TIMEOUT:-600}"
    ;;
  attest)
    case "$R" in acceptance-tester|product-owner) ;; *) die "ein manuelles Gate belegen nur acceptance-tester oder product-owner, nicht $R" ;; esac
    [ $# -ge 4 ] || die "Aufruf: bin/gates.sh attest <nr> <gate> \"<beleg>\""
    with_lock "$TICKETS_DIR/$TICKET/.gates.lock" \
      python3 "$BIN_DIR/gates.py" attest "$LEDGER" "$3" "$HEAD8" "$R" "$4"
    ;;
  *) die "unbekannter Befehl '$CMD' — run oder attest" ;;
esac
