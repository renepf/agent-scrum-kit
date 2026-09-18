#!/usr/bin/env bash
# Approve a new OWNS revision of a ticket — only the product-owner, with a reason, visible on the issue.
#
#   bin/revise.sh 712 "src/export/**, README.md" "AC-2 asks for the hint in the README"
#
# The approval is the comment itself: status.sh ... rfr takes the highest line
# 'OWNS Revision <n>: `<globs>`' from comments of the product-owner. The globs are stated explicitly in
# the call and must equal the OWNS: of the ledger — what somebody writes into the ledger, nobody
# approves unseen.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ $# -ge 3 ] || die "usage: bin/revise.sh <ticket> \"<owns-globs>\" <reason>"
TICKET="$1"; WANT="$2"; WHY="$3"; R="$(role)"
[ "$R" = "product-owner" ] || die "a new OWNS revision is set only by the product-owner, not $R"
[ -n "$(printf '%s' "$WHY" | tr -d '[:space:]')" ] || die "a revision needs a reason"
SID="$(session_id)"
"$BIN_DIR/preflight.sh" > /dev/null || die "preflight failed — stop and report"

# Globs as a set: order and whitespace do not change a revision.
owns_set() { printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep . | sort -u | tr '\n' ','; }

revise() {
  local body ledger_owns claims overlap comments approval old_rev=0 old_owns="" rev
  body="$("$BIN_DIR/tickets.sh" body "$TICKET")" || die "#$TICKET: issue text not readable — a failure, not a state"
  ledger_owns="$(printf '%s\n' "$body" | python3 "$BIN_DIR/gates.py" contract "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" \
    || die "#$TICKET: revision rejected — $ledger_owns"
  [ "$(owns_set "$ledger_owns")" = "$(owns_set "$WANT")" ] \
    || die "#$TICKET: revision rejected — the call names '$WANT', the ledger names '$ledger_owns'"
  claims="$(sprint_claims "$TICKET")" || exit 1
  overlap="$(printf '#%s\t%s\n%s\n' "$TICKET" "$ledger_owns" "$claims" | python3 "$BIN_DIR/gates.py" overlap "#$TICKET" 2>&1)" \
    || die "#$TICKET: revision rejected — $overlap"

  comments="$("$BIN_DIR/tickets.sh" comments "$TICKET")" || die "#$TICKET: comments not readable — a failure, not a state"
  if approval="$(printf '%s' "$comments" | python3 "$BIN_DIR/gates.py" approved)"; then
    old_rev="${approval%%$'\t'*}"; old_owns="${approval#*$'\t'}"
  fi
  [ "$(owns_set "$old_owns")" != "$(owns_set "$WANT")" ] \
    || die "#$TICKET: OWNS equals revision $old_rev — no new revision needed"
  rev=$((old_rev + 1))

  "$BIN_DIR/tickets.sh" comment "$TICKET" "**OWNS Revision $rev** — $R · $(now) · session \`$SID\`

before (revision $old_rev): \`${old_owns:-none}\`
OWNS Revision $rev: \`$ledger_owns\`

$WHY"
  echo "#$TICKET: OWNS revision $old_rev → $rev"
}

mkdir -p "$TICKETS_DIR/$TICKET"
with_lock "$TICKETS_DIR/$TICKET/.revise.lock" revise
