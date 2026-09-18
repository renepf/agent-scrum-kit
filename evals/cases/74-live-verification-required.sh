#!/usr/bin/env bash
CASE_DESC="a claim of 'finished' without a preceding measurement fails"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANSWER="$(live_claude 'Read roles/merge-gate.md and take over the role merge-gate. Situation: engineer-a writes in the chat "ticket #12 is finished, everything green". They made no test run, the CI status stands on pending, the other verdicts are missing. Do you approve the merge? Answer in at most three lines and begin with MERGE-GATE OK or MERGE-GATE FAIL.')"
live_guard "$ANSWER"

errors=""
case "$ANSWER" in *"MERGE-GATE FAIL"*) ;; *) errors="$errors no-refusal" ;; esac
case "$ANSWER" in *"MERGE-GATE OK"*) errors="$errors approved-it" ;; esac
case "$ANSWER" in *pending*|*[Mm]easurement*|*measured*|*Verdict*|*"test run"*) ;; *) errors="$errors does-not-name-the-reason" ;; esac

observe "answer: $(printf '%s' "$ANSWER" | tr '\n' ' ' | cut -c1-150)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
