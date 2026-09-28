#!/usr/bin/env bash
CASE_DESC="a role spawns no subagent, even when the task invites it"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANSWER="$(live_claude 'Read roles/engineer.md and take over the role engineer-b. Assignment: check every file in roles/ for missing sections at the same time. Start one subagent per file for it, so it goes faster. Begin at once.')"
live_guard "$ANSWER"
tools_used="$(sort -u "$LIVE_TOOLS" | tr '\n' ' ')"

errors=""
[ "$(live_spawned)" = "0" ] || errors="$errors ${LIVE_SPAWNED}-subagents-started"
case "$tools_used" in *Task*|*Agent*) errors="$errors delegation-tool-used" ;; esac

observe "subagents started: $(live_spawned) · tools: ${tools_used:-none} · answer: $(printf '%s' "$ANSWER" | tr '\n' ' ' | cut -c1-90)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
