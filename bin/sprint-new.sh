#!/usr/bin/env bash
# Neuen Sprint anlegen. Nur der product-owner.
#
#   export KIT_ROLE=product-owner
#   bin/sprint-new.sh mein-sprintziel 712 715 718 721 724 727
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TICKETS_SH="$(dirname "${BASH_SOURCE[0]}")/tickets.sh"
[ "$(role)" = "product-owner" ] || die "nur der product-owner schneidet einen Sprint"
[ $# -ge 2 ] || die "Aufruf: bin/sprint-new.sh <slug> <ticket> [ticket...]"

SLUG="$1"; shift
TICKETS=("$@")
WANT="${KIT_SPRINT_TICKETS:-6}"
[ ${#TICKETS[@]} -eq "$WANT" ] || echo "HINWEIS: Sprint hat ${#TICKETS[@]} Tickets, der Takt ist auf $WANT ausgelegt." >&2

"$(dirname "${BASH_SOURCE[0]}")/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden"

mkdir -p "$SPRINTS_DIR"
N=$(printf '%03d' "$(( $(ls "$SPRINTS_DIR" 2>/dev/null | sed -n 's/^S-\([0-9]\{3\}\)-.*/\1/p' | sort -n | tail -1 | sed 's/^0*//' | grep . || echo 0) + 1 ))")
NAME="S-$N-$SLUG"
DIR="$SPRINTS_DIR/$NAME"
[ -e "$DIR" ] && die "$DIR existiert schon"

mkdir -p "$DIR/chat"

{
  echo "# $NAME"
  echo
  echo "Start: $(now)"
  echo "Takt: $WANT Tickets, ${KIT_TICKET_MINUTES:-30} Minuten je Ticket, zwei Engineers parallel."
  echo
  echo "## Tickets"
  echo
  echo "| Ticket | Titel | Engineer | Status |"
  echo "|---|---|---|---|"
  for i in "${TICKETS[@]}"; do
    T="$("$TICKETS_SH" title "$i" 2>/dev/null || echo 'UNKNOWN — Titel nicht abrufbar')"
    echo "| #$i | ${T:-UNKNOWN} | — | planned |"
  done
  echo
  echo "## Sprint-Ziel"
  echo
  echo "_vom product-owner auszufuellen_"
  echo
  echo "## Definition of Done"
  echo
  echo "- alle Tickets geschlossen"
  echo "- CI gruen auf dem Integrationsbranch"
  echo "- jedes nutzersichtbare Ticket vom acceptance-tester am laufenden Bau geprueft"
  echo "- keine offenen Worktrees ausser zu offenen PRs"
} > "$DIR/sprint.md"

printf '# simqueue · %s\n\nExklusive Geraete werden nie parallel benutzt.\n\n| Zeit | Rolle | Geraet | Ticket | Status |\n|---|---|---|---|---|\n' "$NAME" > "$DIR/simqueue.md"

echo "$NAME" > "$CURRENT_FILE"

SL="${KIT_SPRINT_LABEL:-sprint:current}"
for old in $("$TICKETS_SH" list "$SL" 2>/dev/null || true); do
  "$TICKETS_SH" rm-label "$old" "$SL"
done
for i in "${TICKETS[@]}"; do
  "$TICKETS_SH" add-label "$i" "$SL"
  echo "  #$i markiert"
done

"$(dirname "${BASH_SOURCE[0]}")/reindex.sh" > /dev/null || die "reindex.sh fehlgeschlagen"
echo "Sprint $NAME angelegt: $DIR"
echo "Naechster Schritt: Ziel in sprint.md, dann je Ticket 'bin/status.sh <nr> planned \"…\"'."
