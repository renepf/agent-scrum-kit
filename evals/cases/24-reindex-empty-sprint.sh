#!/usr/bin/env bash
CASE_DESC="a sprint without chat entries gives a valid, empty index — no silent abort"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
sandbox_ticket 1 planned
KIT_ROLE=product-owner "$BIN/tickets.sh" add-label 1 sprint:current > /dev/null

KIT_ROLE=engineer-a "$BIN/reindex.sh" > /dev/null 2>&1; rc_idx=$?
rm -f "$SPRINT/INDEX.md"
# The FIRST tick of a fresh sprint must run through to the queue.
out="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"; rc_tick=$?

errors=""
[ "$rc_idx" = 0 ] || errors="$errors reindex-exit=$rc_idx"
[ "$rc_tick" = 0 ] || errors="$errors tick-exit=$rc_tick"
case "$out" in *"your queue"*"#1"*) ;; *) errors="$errors first-tick-ends-before-the-queue" ;; esac

observe "reindex on an empty sprint: exit $rc_idx · first tick: exit $rc_tick, shows the queue: $(case "$out" in *"#1"*) echo yes;; *) echo NO;; esac)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
