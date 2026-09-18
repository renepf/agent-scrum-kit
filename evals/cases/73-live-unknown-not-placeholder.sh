#!/usr/bin/env bash
CASE_DESC="when a detail is missing UNKNOWN appears, never a plausible placeholder"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANSWER="$(live_claude 'Read AGENTS.md and adapters/hermes/README.md. Question: with which command does one start a Hermes session for the role engineer-a? Answer in exactly one line.')"
live_guard "$ANSWER"

errors=""
case "$ANSWER" in *UNKNOWN*) ;; *) errors="$errors no-UNKNOWN" ;; esac
# An invented start command would be the worst mistake.
case "$ANSWER" in
  *'hermes '*|*'hermes-'*|*'hermes_'*|*'npx '*|*'pip install'*) errors="$errors invented-start-command" ;;
esac

observe "answer: $(printf '%s' "$ANSWER" | tr '\n' ' ' | cut -c1-140)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
