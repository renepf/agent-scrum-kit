#!/usr/bin/env bash
# Ein Ticket in 'in-review' mitbesitzen, ohne den Status zu aendern.
# Pruefer arbeiten parallel: wer zuerst aufnimmt, setzt in-review; die anderen steigen hiermit ein.
#
#   bin/claim.sh 795
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ $# -ge 1 ] || die "Aufruf: bin/claim.sh <ticket>"
R="$(role)"
case " qa-ruthless simplicity-reviewer security-engineer " in *" $R "*) ;; *) die "claim.sh ist nur fuer Pruefer in 'in-review', nicht $R" ;; esac
"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden"
ST="$("$BIN_DIR/tickets.sh" labels "$1" | grep "^$KIT_LABEL_PREFIX" || true)"
[ "$ST" = "${KIT_LABEL_PREFIX}in-review" ] || die "#$1 steht auf '${ST:-ohne Status}', nicht in-review. Aus rfr nimmst du mit status.sh auf."
"$BIN_DIR/tickets.sh" add-label "$1" "$KIT_OWNER_PREFIX$R"
[ ! -f "$CURRENT_FILE" ] || KIT_ROLE="$R" "$BIN_DIR/say.sh" "#$1 · $R nimmt in-review mit auf" <<<"$KIT_OWNER_PREFIX$R gesetzt." > /dev/null
echo "#$1 → $KIT_OWNER_PREFIX$R"
