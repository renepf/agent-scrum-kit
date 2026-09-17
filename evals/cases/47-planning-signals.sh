#!/usr/bin/env bash
CASE_DESC="sprint-new.sh lehnt ein Ticket ohne vollstaendige Artefaktkette ab und legt nichts an; der Tick zeigt dem requirements-engineer die Luecken im backlog und dem product-owner die Kanban-Zahlen mit Planungsstopp, anderen Rollen nicht"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
shopt -s extglob   # fuer die Negativmuster !(...)

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
pruef() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tr '\n' ' ' | head -c 130)'" ;; esac; }
kette() { mkdir -p "$SANDBOX/tickets/$1"; for a in intent.md spec.md plan.md; do printf 'inhalt\n' > "$SANDBOX/tickets/$1/$a"; done; }

# --- sprint-new.sh: ein Ticket ohne vollstaendige Kette kommt nicht in den Sprint
for i in 11 12; do sandbox_plannable "$i" "src/m$i/**" > /dev/null; sandbox_ticket "$i" backlog; done   # eigene OWNS je Ticket, sonst lehnt die Ueberlappung ab
rm -f "$SANDBOX/tickets/12/spec.md"
vorher="$(ls "$SANDBOX/sprints" 2>/dev/null | tr '\n' ' ')"
out="$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" ziel 11 12 2>&1)"; rc=$?
nachher="$(ls "$SANDBOX/sprints" 2>/dev/null | tr '\n' ' ')"
n=$((n + 1)); [ "$rc" != 0 ] || fail "a-Sprint-trotz-Luecke"
pruef a-Meldung "$out" '*#12*spec.md*'
n=$((n + 1)); [ "$vorher" = "$nachher" ] || fail "a-Sprint-angelegt:'$nachher'"

kette 12
out="$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" ziel 11 12 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "b-vollstaendig-abgelehnt:'$(printf '%s' "$out" | tail -1 | head -c 110)'"

# --- Tick: der requirements-engineer sieht die Luecken im backlog
sandbox_issue 13 '{"body":"AC-1: etwas","labels":["status:backlog"]}'
mkdir -p "$SANDBOX/tickets/13"; printf 'nur das Problem\n' > "$SANDBOX/tickets/13/intent.md"
re="$(KIT_ROLE=requirements-engineer "$BIN/tick.sh" 2>&1)"
pruef c-RE-sieht-Ticket "$re" '*#13*'
pruef d-RE-sieht-fehlende-Glieder "$re" '*spec.md*plan.md*'
pruef e-RE-ohne-Luecke-nicht-gelistet "$re" '!(*#11 fehlt*)'

# --- Tick: der product-owner sieht die Kanban-Zahlen, der Engineer nicht
sandbox_issue 11 '{"labels":["status:in-progress","sprint:current"]}'
po="$(KIT_ROLE=product-owner "$BIN/tick.sh" 2>&1)"
pruef f-PO-Kanban "$po" '*Kanban*'
pruef g-PO-geplant "$po" '*geplant*'
pruef h-PO-in-Arbeit "$po" '*in Arbeit*'
eng="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
pruef i-Engineer-ohne-Kanban "$eng" '!(*Kanban*)'

# --- Planungsstopp: drei Tickets in der Pruefschlange
# Nur Tickets mit Sprint-Label zaehlen in der Kanban-Sicht.
for i in 21 22 23; do sandbox_plannable "$i" "src/m$i/**" > /dev/null; sandbox_issue "$i" '{"labels":["status:rfr","sprint:current"]}'; done
po2="$(KIT_ROLE=product-owner "$BIN/tick.sh" 2>&1)"
pruef j-Stau-erkannt "$po2" '*Planungsstopp*'
sandbox_issue 23 '{"labels":["status:done","sprint:current"]}'
po3="$(KIT_ROLE=product-owner "$BIN/tick.sh" 2>&1)"
pruef k-Stau-aufgeloest "$po3" '!(*Planungsstopp*)'

observe "$n Pruefungen, $falsch falsch${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ "$falsch" = 0 ]
