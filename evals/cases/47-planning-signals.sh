#!/usr/bin/env bash
CASE_DESC="sprint-new.sh refuses a ticket without a complete artefact chain and creates nothing; the tick shows the requirements-engineer the gaps in the backlog and the product-owner the kanban numbers with the planning stop, other roles neither"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
shopt -s extglob   # for the negative patterns !(...)

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
check() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tr '\n' ' ' | head -c 130)'" ;; esac; }
chain() { mkdir -p "$SANDBOX/tickets/$1"; for a in intent.md spec.md plan.md; do printf 'inhalt\n' > "$SANDBOX/tickets/$1/$a"; done; }

# --- sprint-new.sh: a ticket without a complete chain does not enter the sprint
for i in 11 12; do sandbox_plannable "$i" "src/m$i/**" > /dev/null; sandbox_ticket "$i" backlog; done   # its own OWNS per ticket, otherwise the overlap check refuses
rm -f "$SANDBOX/tickets/12/spec.md"
before="$(ls "$SANDBOX/sprints" 2>/dev/null | tr '\n' ' ')"
out="$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" ziel 11 12 2>&1)"; rc=$?
after="$(ls "$SANDBOX/sprints" 2>/dev/null | tr '\n' ' ')"
n=$((n + 1)); [ "$rc" != 0 ] || fail "a-sprint-despite-gap"
check a-message "$out" '*#12*spec.md*'
n=$((n + 1)); [ "$before" = "$after" ] || fail "a-sprint-created:'$after'"

chain 12
out="$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" ziel 11 12 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "b-complete-rejected:'$(printf '%s' "$out" | tail -1 | head -c 110)'"

# --- The tick: the requirements-engineer sees the gaps in the backlog
sandbox_issue 13 '{"body":"AC-1: etwas","labels":["status:backlog"]}'
mkdir -p "$SANDBOX/tickets/13"; printf 'only the problem\n' > "$SANDBOX/tickets/13/intent.md"
re="$(KIT_ROLE=requirements-engineer "$BIN/tick.sh" 2>&1)"
check c-RE-sees-ticket "$re" '*#13*'
check d-RE-sees-missing-links "$re" '*spec.md*plan.md*'
check e-RE-without-gap-not-listed "$re" '!(*#11 missing*)'

# --- The tick: the product-owner sees the kanban numbers, the engineer does not
sandbox_issue 11 '{"labels":["status:in-progress","sprint:current"]}'
po="$(KIT_ROLE=product-owner "$BIN/tick.sh" 2>&1)"
check f-PO-kanban "$po" '*kanban*'
check g-PO-planned "$po" '*target at least*'
check h-PO-in-progress "$po" '*· in progress *'
eng="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
check i-engineer-without-kanban "$eng" '!(*kanban*)'

# --- planning stop: three tickets in the review queue
# Only tickets with the sprint label count in the kanban view.
for i in 21 22 23; do sandbox_plannable "$i" "src/m$i/**" > /dev/null; sandbox_issue "$i" '{"labels":["status:rfr","sprint:current"]}'; done
po2="$(KIT_ROLE=product-owner "$BIN/tick.sh" 2>&1)"
check j-jam-detected "$po2" '*planning stop*'
sandbox_issue 23 '{"labels":["status:done","sprint:current"]}'
po3="$(KIT_ROLE=product-owner "$BIN/tick.sh" 2>&1)"
check k-jam-cleared "$po3" '!(*planning stop*)'

observe "$n checks, $wrong wrong${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ "$wrong" = 0 ]
