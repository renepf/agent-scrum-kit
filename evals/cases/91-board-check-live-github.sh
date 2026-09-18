#!/usr/bin/env bash
CASE_DESC="the configured GitHub Project mirrors the status model (a real gh call, reads only)"
CASE_KIND="gh"
CASE_HOST="github"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Reads the kit's own kit.env, not the sandbox: what is checked is YOUR board.
unset KIT_ENV_FILE KIT_BOARD_ENV_FILE
[ -f "$KIT_ROOT/kit.env" ] || { echo "OBSERVED: BLOCKED — kit.env is missing"; exit 3; }
grep -q '^KIT_BOARD="github-project"' "$KIT_ROOT/kit.env" || { echo "OBSERVED: BLOCKED — KIT_BOARD is not github-project"; exit 3; }
out="$("$BIN/board-check.sh" 2>&1)"; rc=$?
case "$out" in *"preflight failed"*|*"not readable"*) echo "OBSERVED: BLOCKED — $(echo "$out" | tail -1)"; exit 3 ;; esac
ok="$(printf '%s' "$out" | grep -c '^OK' || true)"; fail="$(printf '%s' "$out" | grep -c '^FAIL' || true)"
observe "$(printf '%s' "$out" | tail -1) · $ok OK, $fail FAIL"
printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/  /'
echo "OBSERVED: $OBSERVED"
[ "$rc" = 0 ]
