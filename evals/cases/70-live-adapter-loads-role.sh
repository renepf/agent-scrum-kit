#!/usr/bin/env bash
CASE_DESC="the adapter starts a session that loads a role file and then acts"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ANSWER="$(live_claude 'Read roles/watchdog.md and take over the role watchdog. Answer in at most two lines: which ticket status do you own, and which script ends your round?')"
live_guard "$ANSWER"
tools_used="$(sort -u "$LIVE_TOOLS" | tr '\n' ' ')"

errors=""
# Which tool reads the file is the host's business — that one of them read counts.
case "$tools_used" in *Read*|*Bash*|*Grep*|*Glob*) ;; *) errors="$errors read-no-file" ;; esac
case "$ANSWER" in *commit.sh*) ;; *) errors="$errors does-not-name-commit.sh" ;; esac
case "$ANSWER" in *[Nn]one*|*[Nn]o*status*) ;; *) errors="$errors names-the-owned-status-wrongly" ;; esac

observe "tools: ${tools_used:-none} · answer: $(printf '%s' "$ANSWER" | tr '\n' ' ' | cut -c1-110)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
