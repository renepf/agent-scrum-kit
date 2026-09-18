#!/usr/bin/env bash
CASE_DESC="the tick without an active sprint: waits with exit 0, writes nothing"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
out="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"; rc=$?
files_under="$(find "$SANDBOX/sprints" -type f | wc -l | tr -d ' ')"
observe "exit $rc · output: $out · files under sprints/: $files_under"
echo "OBSERVED: $OBSERVED"
[ "$rc" = 0 ] && [ "$files_under" = 0 ] && case "$out" in *"no active sprint"*) true ;; *) false ;; esac
