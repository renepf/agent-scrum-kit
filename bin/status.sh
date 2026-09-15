#!/usr/bin/env bash
# Ticketstatus wechseln — Board, Label und Besitz in einem Kommando.
#
#   bin/status.sh 712 in-progress "aufgenommen, Worktree offen"
#
# Reihenfolge, die zwei echte Fehlerquellen schliesst:
#   0. ALLES pruefen, bevor irgendetwas geschrieben wird: Kante, Rolle, Besitz, Gate.
#      Eine abgelehnte Transition fasst weder Board noch Label an.
#   1. Board zuerst (die Wahrheit). Scheitert es, bleibt das Label unveraendert.
#   2. Label als Spiegel, owner:<rolle> als Besitz, Kommentar, Chat.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

T="$BIN_DIR/tickets.sh"
P="$KIT_LABEL_PREFIX"; O="$KIT_OWNER_PREFIX"
REVIEWERS="qa-ruthless simplicity-reviewer security-engineer"
ENGINEERS="engineer-a engineer-b"

# Die einzigen erlaubten Kanten. Zwei davon sind die Rueckwaertskante.
EDGES="
backlog>planned
planned>in-progress
in-progress>rfr
rfr>in-review
in-review>rft
rft>in-testing
in-testing>done
in-review>in-progress
in-testing>in-progress
"

[ $# -ge 2 ] || die "Aufruf: bin/status.sh <ticket> <status> [kommentar]"
TICKET="$1"; NEW="$2"; NOTE="${3:-}"
case " $KIT_STATES " in *" $NEW "*) ;; *) die "unbekannter Status '$NEW'. Erlaubt: $KIT_STATES" ;; esac

R="$(role)"
SID="$(session_id)"
"$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden, nicht umgehen"

in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

LABELS="$("$T" labels "$TICKET")" || die "#$TICKET: Labels nicht lesbar — Fehlschlag, kein Zustand"
OLD="$(printf '%s\n' "$LABELS" | grep "^$P" | head -1 | sed "s|^$P||" || true)"
[ -n "$OLD" ] || OLD="backlog"
OWNERS_NOW="$(printf '%s\n' "$LABELS" | grep "^$O" | sed "s|^$O||" | tr '\n' ' ' || true)"

[ "$OLD" != "$NEW" ] || die "#$TICKET steht bereits auf '$NEW' — kein Uebergang"
case "$EDGES" in
  *"$OLD>$NEW"*) ;;
  *) die "unerlaubter Uebergang '$OLD' → '$NEW'. Erlaubt ab '$OLD': $(printf '%s\n' "$EDGES" | grep "^$OLD>" | sed "s|^$OLD>||" | tr '\n' ' ')" ;;
esac

# --- 0. Rolle, Besitz, Gate — vor jedem Schreibzugriff ---------------------------
OWNER=""; KEEP=""
case "$NEW" in
  backlog|planned)
    [ "$R" = "product-owner" ] || die "'$NEW' setzt nur der product-owner, nicht $R"
    if [ "$NEW" = "planned" ]; then
      # Kein Code ohne pruefbaren Vertrag: jede AC des Issues hat ein Gate im Ledger.
      LEDGER="$TICKETS_DIR/$TICKET/GATES.md"
      [ -f "$LEDGER" ] || die "#$TICKET: planned abgelehnt — kein Ledger unter $LEDGER. Je AC ein Gate, Format in bin/gates.py"
      BODY="$("$T" body "$TICKET")" || die "#$TICKET: Issue-Text nicht lesbar — Fehlschlag, kein Zustand"
      GATE_MSG="$(printf '%s\n' "$BODY" | python3 "$BIN_DIR/gates.py" planned "$LEDGER" 2>&1)" \
        || die "#$TICKET: planned abgelehnt — $GATE_MSG"
    fi
    ;;
  in-progress)
    if in_list "$R" "$ENGINEERS"; then
      [ "$OLD" = "planned" ] || die "$R nimmt nur aus 'planned' auf. Eine Rueckweisung setzt der Pruefer."
      OWNER="$R"
    else
      case "$OLD" in
        in-review)  in_list "$R" "$REVIEWERS" || die "aus 'in-review' weist nur ein Pruefer zurueck, nicht $R" ;;
        in-testing) in_list "$R" "acceptance-tester merge-gate product-owner" || die "aus 'in-testing' weisen nur acceptance-tester, merge-gate oder product-owner zurueck, nicht $R" ;;
      esac
      # Rueckwaertskante: der Engineer ist der, der das Ticket zuletzt auf in-progress gesetzt
      # hat — steht in den Kommentaren, die dieses Skript selbst schreibt. Nicht raten.
      IP="$(board_name in-progress)"
      OWNER="$("$T" comments "$TICKET" | python3 -c '
import json, re, sys
head = "**" + sys.argv[1] + "** — "
hits = [m.group(1) for b in json.load(sys.stdin)
        for m in [re.match(re.escape(head) + r"(engineer-[ab]) ", b)] if m]
print(hits[-1] if hits else "")
' "$IP")"
      [ -n "$OWNER" ] || die "#$TICKET: kein frueherer Engineer in der Kommentarhistorie — nicht raten"
    fi
    ;;
  rfr)
    in_list "$R" "$ENGINEERS" || die "'rfr' setzt nur ein Engineer, nicht $R"
    in_list "$R" "$OWNERS_NOW" || die "#$TICKET gehoert nicht $R (Besitz: ${OWNERS_NOW:-niemand})"
    ;;
  in-review)
    in_list "$R" "$REVIEWERS" || die "'in-review' nimmt nur ein Pruefer auf, nicht $R"
    OWNER="$R"; KEEP="$REVIEWERS"
    ;;
  rft)
    in_list "$R" "$REVIEWERS" || die "'rft' setzt nur ein Pruefer, nicht $R"
    verdicts_missing "$TICKET" "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"
    [ -z "$VERDICT_MISSING" ] || die "#$TICKET: rft abgelehnt — im PR #$VERDICT_PR fehlt fuer HEAD $VERDICT_HEAD8:$VERDICT_MISSING. Format der ersten Zeile: '<VERDICT> — HEAD \`$VERDICT_HEAD8\`, ...'"
    ;;
  in-testing)
    [ "$R" = "acceptance-tester" ] || die "'in-testing' nimmt nur der acceptance-tester auf, nicht $R"
    OWNER="$R"
    ;;
  done)
    case "$R" in
      product-owner) ;;
      merge-gate)
        verdicts_missing "$TICKET" "PO OK"
        [ -z "$VERDICT_MISSING" ] || die "#$TICKET: done abgelehnt — kein 'PO OK — HEAD \`$VERDICT_HEAD8\`' im PR #$VERDICT_PR. Der product-owner hat das letzte Wort."
        ;;
      *) die "'done' setzt nur der product-owner, oder merge-gate mit PO OK — nicht $R" ;;
    esac
    ;;
esac

# --- 1. Board zuerst ------------------------------------------------------------
if [ "$KIT_BOARD" = "github-project" ]; then
  KEY="KIT_OPTION_$(echo "$NEW" | tr 'a-z-' 'A-Z_')"
  OPT="${!KEY:-}"
  [ -n "$OPT" ] || die "keine Board-Option fuer '$NEW' in board.env — bin/board-check.sh --write laufen lassen"
  "$T" board-set "$TICKET" "$OPT" "$(board_name "$NEW")" || die "Board-Status nicht gesetzt — Label bleibt absichtlich unveraendert"
fi

# --- 2. Label als Spiegel -------------------------------------------------------
for l in $(printf '%s\n' "$LABELS" | grep "^$P" || true); do
  "$T" rm-label "$TICKET" "$l"
done
[ "$NEW" = "done" ] || "$T" add-label "$TICKET" "$P$NEW"

# Besitz ueber owner:<rolle>. Alle Sessions teilen oft EINEN Account — der Assignee kann
# engineer-a und engineer-b nicht unterscheiden, das Label kann es.
for o in $OWNERS_NOW; do
  if [ "$o" = "$OWNER" ] || in_list "$o" "$KEEP"; then continue; fi
  "$T" rm-label "$TICKET" "$O$o"
done
[ -z "$OWNER" ] || in_list "$OWNER" "$OWNERS_NOW" || "$T" add-label "$TICKET" "$O$OWNER"
if [ -z "$OWNER" ]; then
  for a in $("$T" assignees "$TICKET"); do "$T" unassign "$TICKET" "$a"; done
fi

"$T" comment "$TICKET" "**$(board_name "$NEW")** — $R · $(now) · session \`$SID\`

${NOTE:-_kein Kommentar_}"

[ "$NEW" != "done" ] || "$T" close "$TICKET"

if [ -f "$CURRENT_FILE" ]; then
  KIT_ROLE="$R" "$BIN_DIR/say.sh" "#$TICKET · $(board_name "$NEW")" <<EOF > /dev/null
${NOTE:-Statuswechsel ohne Kommentar.}
EOF
fi

echo "#$TICKET: $OLD → $NEW${OWNER:+ (owner:$OWNER)}"
