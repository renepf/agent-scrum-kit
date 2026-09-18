#!/usr/bin/env bash
CASE_DESC="the tick shows an engineer the rejection before any new ticket, another engineer not"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 21 '{"title":"a rejected ticket","labels":["sprint:current"],"pr":{"number":210,"head":"abcabcabc1","comments":[]}}'
sandbox_plannable 21
sandbox_issue 22 '{"title":"a new ticket","labels":["sprint:current","status:planned"]}'
KIT_ROLE=product-owner "$BIN/status.sh" 21 planned x > /dev/null
KIT_ROLE=engineer-a "$BIN/status.sh" 21 in-progress x > /dev/null
KIT_ROLE=engineer-a "$BIN/status.sh" 21 rfr x > /dev/null
KIT_ROLE=qa-ruthless "$BIN/status.sh" 21 in-review x > /dev/null
KIT_ROLE=qa-ruthless "$BIN/status.sh" 21 in-progress "boundary value 0 untested" > /dev/null

a="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"
b="$(KIT_ROLE=engineer-b "$BIN/tick.sh" 2>&1)"
pos_rejected="$(printf '%s\n' "$a" | grep -n 'REJECTED' | head -1 | cut -d: -f1)"
pos_new="$(printf '%s\n' "$a" | grep -n '#22 ' | head -1 | cut -d: -f1)"

errors=""
[ -n "$pos_rejected" ] || errors="$errors no-rejection-for-engineer-a"
[ -n "$pos_new" ] || errors="$errors new-ticket-missing"
[ -n "$pos_rejected" ] && [ -n "$pos_new" ] && [ "$pos_rejected" -lt "$pos_new" ] || errors="$errors order"
printf '%s' "$a" | grep -q 'boundary value 0 untested' || errors="$errors finding-not-shown"
printf '%s' "$b" | grep -q 'REJECTED' && errors="$errors engineer-b-sees-a-foreign-rejection"

observe "engineer-a: the rejection on line $pos_rejected, the new ticket on line $pos_new · engineer-b sees no foreign rejection: $(printf '%s' "$b" | grep -q REJECTED && echo NO || echo yes)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
