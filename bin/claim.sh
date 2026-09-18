#!/usr/bin/env bash
# Co-own a ticket in 'in-review' without changing the status.
# Reviewers work in parallel: whoever picks it up first sets in-review; the others join with this.
#
#   bin/claim.sh 795
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ $# -ge 1 ] || die "usage: bin/claim.sh <ticket>"
R="$(role)"
case " qa-ruthless simplicity-reviewer security-engineer " in *" $R "*) ;; *) die "claim.sh is only for reviewers in 'in-review', not $R" ;; esac
"$BIN_DIR/preflight.sh" > /dev/null || die "preflight failed — stop and report"
ST="$("$BIN_DIR/tickets.sh" labels "$1" | grep "^$KIT_LABEL_PREFIX" || true)"
[ "$ST" = "${KIT_LABEL_PREFIX}in-review" ] || die "#$1 is on '${ST:-without status}', not in-review. Out of rfr you pick up with status.sh."
"$BIN_DIR/tickets.sh" add-label "$1" "$KIT_OWNER_PREFIX$R"
[ ! -f "$CURRENT_FILE" ] || KIT_ROLE="$R" "$BIN_DIR/say.sh" "#$1 · $R co-owns in-review" <<<"$KIT_OWNER_PREFIX$R set." > /dev/null
echo "#$1 → $KIT_OWNER_PREFIX$R"
