#!/usr/bin/env bash
# Create a new sprint. Only the product-owner.
#
#   export KIT_ROLE=product-owner
#   bin/sprint-new.sh my-sprint-goal 712 715 718 721 724 727
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TICKETS_SH="$(dirname "${BASH_SOURCE[0]}")/tickets.sh"
[ "$(role)" = "product-owner" ] || die "only the product-owner cuts a sprint"
[ $# -ge 2 ] || die "usage: bin/sprint-new.sh <slug> <ticket> [ticket...]"

SLUG="$1"; shift
TICKETS=("$@")
WANT="${KIT_SPRINT_TICKETS:-6}"
[ ${#TICKETS[@]} -eq "$WANT" ] || echo "NOTE: the sprint has ${#TICKETS[@]} tickets, the cadence is built for $WANT." >&2

"$(dirname "${BASH_SOURCE[0]}")/preflight.sh" > /dev/null || die "preflight failed — stop and report"

# No overlap at the cut: tickets with a ledger must not claim shared paths.
# Tickets without a ledger are checked later by status.sh ... planned. Before any write.
CLAIMS=""
for i in "${TICKETS[@]}"; do
  [ -f "$TICKETS_DIR/$i/GATES.md" ] && CLAIMS="$CLAIMS#$i	@$TICKETS_DIR/$i/GATES.md
"
done
OVERLAP="$(printf '%s' "$CLAIMS" | python3 "$BIN_DIR/gates.py" overlap 2>&1)" || die "sprint rejected — $OVERLAP"

# Artefact chain per ticket: without intent.md, spec.md and plan.md a ticket does not enter the sprint.
# Otherwise it stalls later at planned and blocks the cadence. The requirements-engineer writes them.
GAP=""
for i in "${TICKETS[@]}"; do
  for a in intent.md spec.md plan.md; do
    grep -q '[^[:space:]]' "$TICKETS_DIR/$i/$a" 2>/dev/null || GAP="$GAP #$i:$a"
  done
done
[ -z "$GAP" ] || die "sprint rejected — artefact chain incomplete:$GAP (requirements-engineer)"

mkdir -p "$SPRINTS_DIR"
N=$(printf '%03d' "$(( $(ls "$SPRINTS_DIR" 2>/dev/null | sed -n 's/^S-\([0-9]\{3\}\)-.*/\1/p' | sort -n | tail -1 | sed 's/^0*//' | grep . || echo 0) + 1 ))")
NAME="S-$N-$SLUG"
DIR="$SPRINTS_DIR/$NAME"
[ -e "$DIR" ] && die "$DIR already exists"

mkdir -p "$DIR/chat"

{
  echo "# $NAME"
  echo
  echo "Start: $(now)"
  echo "Cadence: $WANT tickets, ${KIT_TICKET_MINUTES:-30} minutes per ticket, two engineers in parallel."
  echo
  echo "## Tickets"
  echo
  echo "| Ticket | Title | Engineer | Status |"
  echo "|---|---|---|---|"
  for i in "${TICKETS[@]}"; do
    T="$("$TICKETS_SH" title "$i" 2>/dev/null || echo 'UNKNOWN — title not retrievable')"
    echo "| #$i | ${T:-UNKNOWN} | — | planned |"
  done
  echo
  echo "## Sprint goal"
  echo
  echo "_to be filled in by the product-owner_"
  echo
  echo "## Definition of Done"
  echo
  echo "- every ticket closed"
  echo "- CI green on the integration branch"
  echo "- every user-visible ticket checked by the acceptance-tester against the running build"
  echo "- no open worktrees except for open PRs"
} > "$DIR/sprint.md"

printf '# simqueue · %s\n\nExclusive devices are never used in parallel.\n\n| Time | Role | Device | Ticket | Status |\n|---|---|---|---|---|\n' "$NAME" > "$DIR/simqueue.md"

echo "$NAME" > "$CURRENT_FILE"

SL="${KIT_SPRINT_LABEL:-sprint:current}"
for old in $("$TICKETS_SH" list "$SL" 2>/dev/null || true); do
  "$TICKETS_SH" rm-label "$old" "$SL"
done
for i in "${TICKETS[@]}"; do
  "$TICKETS_SH" add-label "$i" "$SL"
  echo "  #$i marked"
done

"$(dirname "${BASH_SOURCE[0]}")/reindex.sh" > /dev/null || die "reindex.sh failed"
echo "sprint $NAME created: $DIR"
echo "Next step: the goal in sprint.md, then per ticket 'bin/status.sh <nr> planned \"…\"'."
