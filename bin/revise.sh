#!/usr/bin/env bash
# Neue OWNS-Revision eines Tickets freigeben — nur der product-owner, mit Grund, sichtbar am Issue.
#
#   bin/revise.sh 712 "src/export/**, README.md" "AC-2 verlangt den Hinweis im README"
#
# Die Freigabe ist der Kommentar selbst: status.sh ... rfr nimmt die hoechste Zeile
# 'OWNS Revision <n>: `<globs>`' aus Kommentaren des product-owner. Die Globs stehen ausdruecklich im
# Aufruf und muessen dem OWNS: des Ledgers gleichen — was jemand ins Ledger schreibt, gibt niemand
# ungesehen frei.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ $# -ge 3 ] || die "Aufruf: bin/revise.sh <ticket> \"<owns-globs>\" <grund>"
TICKET="$1"; WANT="$2"; WHY="$3"; R="$(role)"
[ "$R" = "product-owner" ] || die "eine neue OWNS-Revision setzt nur der product-owner, nicht $R"
[ -n "$(printf '%s' "$WHY" | tr -d '[:space:]')" ] || die "eine Revision braucht einen Grund"
SID="$(session_id)"
"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden"

# Globs als Menge: Reihenfolge und Leerzeichen aendern keine Revision.
owns_set() { printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep . | sort -u | tr '\n' ','; }

revise() {
  local body ledger_owns claims overlap comments approval old_rev=0 old_owns="" rev
  body="$("$BIN_DIR/tickets.sh" body "$TICKET")" || die "#$TICKET: Issue-Text nicht lesbar — Fehlschlag, kein Zustand"
  ledger_owns="$(printf '%s\n' "$body" | python3 "$BIN_DIR/gates.py" contract "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" \
    || die "#$TICKET: Revision abgelehnt — $ledger_owns"
  [ "$(owns_set "$ledger_owns")" = "$(owns_set "$WANT")" ] \
    || die "#$TICKET: Revision abgelehnt — der Aufruf nennt '$WANT', das Ledger nennt '$ledger_owns'"
  claims="$(sprint_claims "$TICKET")" || exit 1
  overlap="$(printf '#%s\t%s\n%s\n' "$TICKET" "$ledger_owns" "$claims" | python3 "$BIN_DIR/gates.py" overlap "#$TICKET" 2>&1)" \
    || die "#$TICKET: Revision abgelehnt — $overlap"

  comments="$("$BIN_DIR/tickets.sh" comments "$TICKET")" || die "#$TICKET: Kommentare nicht lesbar — Fehlschlag, kein Zustand"
  if approval="$(printf '%s' "$comments" | python3 "$BIN_DIR/gates.py" approved)"; then
    old_rev="${approval%%$'\t'*}"; old_owns="${approval#*$'\t'}"
  fi
  [ "$(owns_set "$old_owns")" != "$(owns_set "$WANT")" ] \
    || die "#$TICKET: OWNS gleich Revision $old_rev — keine neue Revision noetig"
  rev=$((old_rev + 1))

  "$BIN_DIR/tickets.sh" comment "$TICKET" "**OWNS Revision $rev** — $R · $(now) · session \`$SID\`

vorher (Revision $old_rev): \`${old_owns:-keine}\`
OWNS Revision $rev: \`$ledger_owns\`

$WHY"
  echo "#$TICKET: OWNS Revision $old_rev → $rev"
}

mkdir -p "$TICKETS_DIR/$TICKET"
with_lock "$TICKETS_DIR/$TICKET/.revise.lock" revise
