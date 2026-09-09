#!/usr/bin/env bash
# Ticketstatus wechseln. Genau EIN Status-Label haengt danach am Ticket.
#
#   bin/status.sh 712 in-progress "aufgenommen, Worktree offen"
#
# Prueft die Kante gegen das Statusmodell aus protocols/LOOP.md. Ein unerlaubter
# Uebergang wird abgelehnt — es gibt keine Abkuerzung durch die Schleife.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TICKETS="$(dirname "${BASH_SOURCE[0]}")/tickets.sh"
P="$KIT_LABEL_PREFIX"

# Erlaubte Kanten. Genau diese, sonst keine.
EDGES="
open>planned
planned>in-progress
in-progress>rfr
rfr>in-review
in-review>rft
in-review>in-progress
rft>in-progress
rft>closed
"

[ $# -ge 2 ] || die "Aufruf: bin/status.sh <ticket> <status> [kommentar]"
TICKET="$1"; NEW="$2"; NOTE="${3:-}"

case " $KIT_STATES closed " in
  *" $NEW "*) ;;
  *) die "unbekannter Status '$NEW'. Erlaubt: $KIT_STATES closed" ;;
esac

R="$(role)"
SID="$(session_id)"

# Preflight: ein fehlgeschlagener Aufruf ist ein Fehlschlag, kein Ergebnis.
"$(dirname "${BASH_SOURCE[0]}")/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden, nicht umgehen"

OLD_LABELS="$("$TICKETS" labels "$TICKET" | grep "^$P" || true)"
OLD="$(echo "$OLD_LABELS" | head -1 | sed "s|^$P||")"
[ -n "$OLD" ] || OLD="open"

if [ "$OLD" = "$NEW" ]; then
  die "Ticket #$TICKET steht bereits auf '$NEW' — kein Uebergang"
fi

case "$EDGES" in
  *"$OLD>$NEW"*) ;;
  *) die "unerlaubter Uebergang '$OLD' → '$NEW'. Erlaubt ab '$OLD': $(echo "$EDGES" | grep "^$OLD>" | sed "s|^$OLD>||" | tr '\n' ' ')" ;;
esac

for l in $OLD_LABELS; do
  [ "$l" = "$P$NEW" ] || "$TICKETS" rm-label "$TICKET" "$l"
done
"$TICKETS" add-label "$TICKET" "$P$NEW"

# Besitz: rfr ist bewusst besitzerlos — das ist das Signal an die Pruefer.
if [ "$NEW" = "rfr" ]; then
  for a in $("$TICKETS" assignees "$TICKET"); do
    "$TICKETS" unassign "$TICKET" "$a"
  done
fi

"$TICKETS" comment "$TICKET" "**$P$NEW** — $R · $(now) · session \`$SID\`

${NOTE:-_kein Kommentar_}"

# Denselben Vorgang im Sprint-Chat spiegeln, damit der Index ihn kennt.
if [ -f "$CURRENT_FILE" ]; then
  KIT_ROLE="$R" "$(dirname "${BASH_SOURCE[0]}")/say.sh" "#$TICKET · $NEW" <<EOF
${NOTE:-Statuswechsel ohne Kommentar.}
EOF
fi

echo "#$TICKET: $OLD → $NEW"
