#!/usr/bin/env bash
# Run the gates of a ticket or attest a manual gate. Format: bin/gates.py.
#
#   bin/gates.sh run <nr>                          in the worktree of the PR, on its HEAD
#   bin/gates.sh attest <nr> <gate> "<evidence>"   attest a manual gate: the reviewing engineer
#                                                  (never the builder) or the product-owner
#
# Every piece of evidence hangs on the HEAD of the linked PR and on the definition of the gate. A push or a
# changed CHECK, EXPECT or CWD line invalidates it. CHECK is shell code from the ledger and runs with the
# rights of this session.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
CMD="${1:-}"; TICKET="${2:-}"
[ -n "$CMD" ] && [ -n "$TICKET" ] || die "usage: bin/gates.sh run <nr> | attest <nr> <gate> \"<evidence>\""
R="$(role)"
LEDGER="$TICKETS_DIR/$TICKET/GATES.md"
[ -f "$LEDGER" ] || die "#$TICKET: no ledger under $LEDGER"
PR_LINE="$("$BIN_DIR/tickets.sh" pr "$TICKET" 2>&1)" || die "#$TICKET: no linked PR readable${PR_LINE:+: $PR_LINE}"
HEAD8="${PR_LINE##* }"

case "$CMD" in
  run)
    HERE="$(git rev-parse HEAD 2>/dev/null)" || die "$(pwd) is not a git worktree — gates run in the worktree of the PR"
    [ "${HERE:0:8}" = "$HEAD8" ] || die "#$TICKET: the worktree is on ${HERE:0:8}, the PR on $HEAD8 — check out the HEAD of the PR first"
    with_lock "$TICKETS_DIR/$TICKET/.gates.lock" \
      python3 "$BIN_DIR/gates.py" run "$LEDGER" "$HEAD8" "$(pwd)" "$R" "${KIT_GATE_TIMEOUT:-600}"
    ;;
  attest)
    # A manual gate is attested by whoever ran the acceptance — since 2026-09-28 that is the
    # REVIEWING engineer, never the one who built the ticket, plus the product-owner as the last word.
    case "$R" in
      engineer-*)
        BUILDER="$(ticket_builder "$TICKET")"
        [ "$R" != "$BUILDER" ] || die "#$TICKET: attest rejected — $R built this ticket. A manual gate is attested by the engineer who ran the acceptance, not by the builder."
        ;;
      product-owner) ;;
      *) die "a manual gate is attested only by the reviewing engineer or the product-owner, not $R" ;;
    esac
    [ $# -ge 4 ] || die "usage: bin/gates.sh attest <nr> <gate> \"<evidence>\""
    with_lock "$TICKETS_DIR/$TICKET/.gates.lock" \
      python3 "$BIN_DIR/gates.py" attest "$LEDGER" "$3" "$HEAD8" "$R" "$4"
    ;;
  *) die "unknown command '$CMD' — run or attest" ;;
esac
