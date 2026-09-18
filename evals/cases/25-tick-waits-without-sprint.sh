#!/usr/bin/env bash
CASE_DESC="without a sprint the tick reports waiting and ends with exit 0"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT

out="$(KIT_ROLE=engineer-a "$BIN/tick.sh" 2>&1)"; rc=$?
errors=""
[ "$rc" = 0 ] || errors="$errors exit=$rc"
case "$out" in *"no active sprint"*) ;; *) errors="$errors no-waiting-message" ;; esac
[ ! -e "$SANDBOX/sprints/CURRENT" ] || errors="$errors created-a-sprint"

observe "exit $rc · output: $(echo "$out" | head -1 | cut -c1-80)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
