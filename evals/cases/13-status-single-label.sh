#!/usr/bin/env bash
CASE_DESC="nach einem Wechsel haengt genau ein Status-Label, rfr nimmt den Assignee ab"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
export KIT_ROLE=engineer-a

sandbox_ticket 7 in-progress
"$BIN/tickets.sh" assign 7 engineer-a > /dev/null
"$BIN/status.sh" 7 rfr "PR offen" > /dev/null 2>&1

n="$("$BIN/tickets.sh" labels 7 | grep -c '^status:')"
lab="$("$BIN/tickets.sh" labels 7 | grep '^status:' | tr '\n' ' ')"
ass="$("$BIN/tickets.sh" assignees 7 | wc -l | tr -d ' ')"
observe "Labels: $n ($lab) · Assignees: $ass"
echo "BEOBACHTET: $OBSERVED"
[ "$n" = 1 ] && [ "$ass" = 0 ]
