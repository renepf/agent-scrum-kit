#!/usr/bin/env bash
# Ticketstatus wechseln. Genau EIN Status-Label haengt danach am Ticket.
#
#   bin/status.sh 712 in-progress "aufgenommen, Worktree offen"
#
# Board (falls konfiguriert) UND Label in einem Kommando, dazu Assignee und Kommentar.
# Prueft die Kante gegen das Statusmodell aus protocols/LOOP.md. Ein unerlaubter
# Uebergang wird abgelehnt — es gibt keine Abkuerzung durch die Schleife.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TICKETS="$(dirname "${BASH_SOURCE[0]}")/tickets.sh"
P="$KIT_LABEL_PREFIX"

# Erlaubte Kanten. Genau diese, sonst keine.
EDGES="
backlog>planned
planned>in-progress
in-progress>rfr
rfr>in-review
in-review>rft
in-review>in-progress
rft>in-testing
in-testing>in-progress
in-testing>done
"

[ $# -ge 2 ] || die "Aufruf: bin/status.sh <ticket> <status> [kommentar]"
TICKET="$1"; NEW="$2"; NOTE="${3:-}"

case " $KIT_STATES " in
  *" $NEW "*) ;;
  *) die "unbekannter Status '$NEW'. Erlaubt: $KIT_STATES" ;;
esac

R="$(role)"
SID="$(session_id)"

# Preflight: ein fehlgeschlagener Aufruf ist ein Fehlschlag, kein Ergebnis.
"$(dirname "${BASH_SOURCE[0]}")/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden, nicht umgehen"

OLD_LABELS="$("$TICKETS" labels "$TICKET" | grep "^$P" || true)"
OLD="$(echo "$OLD_LABELS" | head -1 | sed "s|^$P||")"
[ -n "$OLD" ] || OLD="backlog"

if [ "$OLD" = "$NEW" ]; then
  die "Ticket #$TICKET steht bereits auf '$NEW' — kein Uebergang"
fi

case "$EDGES" in
  *"$OLD>$NEW"*) ;;
  *) die "unerlaubter Uebergang '$OLD' → '$NEW'. Erlaubt ab '$OLD': $(echo "$EDGES" | grep "^$OLD>" | sed "s|^$OLD>||" | tr '\n' ' ')" ;;
esac

# 1) Board zuerst, falls konfiguriert. Scheitert es, bleibt das Label absichtlich stehen —
#    sonst laufen Board und Label auseinander.
"$TICKETS" set-board "$TICKET" "$NEW" || die "Board-Status fuer #$TICKET nicht gesetzt — Label unveraendert, Zustand pruefen, nicht raten"

# 2) Label als Spiegel. "done" traegt kein Label; das Ticket wird geschlossen.
for l in $OLD_LABELS; do
  [ "$l" = "$P$NEW" ] || "$TICKETS" rm-label "$TICKET" "$l"
done
if [ "$NEW" = "done" ]; then
  "$TICKETS" close "$TICKET"
else
  "$TICKETS" add-label "$TICKET" "$P$NEW"
fi

# 3) Besitz: rfr und rft sind bewusst besitzerlos — das ist das Signal an die naechste Rolle.
case "$NEW" in
  rfr|rft)
    for a in $("$TICKETS" assignees "$TICKET"); do
      "$TICKETS" unassign "$TICKET" "$a"
    done
    ;;
esac

"$TICKETS" comment "$TICKET" "**$P$NEW** — $R · $(now) · session \`$SID\`

${NOTE:-_kein Kommentar_}"

# Denselben Vorgang im Sprint-Chat spiegeln, damit der Index ihn kennt.
if [ -f "$CURRENT_FILE" ]; then
  KIT_ROLE="$R" "$(dirname "${BASH_SOURCE[0]}")/say.sh" "#$TICKET · $NEW" <<EOF
${NOTE:-Statuswechsel ohne Kommentar.}
EOF
fi

echo "#$TICKET: $OLD → $NEW"
