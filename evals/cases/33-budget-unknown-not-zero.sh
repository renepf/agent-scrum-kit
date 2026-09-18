#!/usr/bin/env bash
CASE_DESC="a missing transcript gives UNKNOWN, never a 0 — and names the right cause"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

{
  printf '# roster\n\n| Time | Role | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | does-not-exist | test-fixture |\n'
} > "$SPRINT/roster.md"

# Case A: the adapter runs but does not find this one id.
KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
a="$(grep '| engineer-a |' "$SPRINT/budget.md")"

# Case B: the host knows no transcripts at all (the adapter is not executable).
chmod -x "$KIT_ROOT/adapters/test-fixture/transcript-path.sh"
KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
b="$(grep '| engineer-a |' "$SPRINT/budget.md")"
chmod +x "$KIT_ROOT/adapters/test-fixture/transcript-path.sh"

errors=""
case "$a" in *UNKNOWN*"not found"*) ;; *) errors="$errors A='$a'" ;; esac
case "$b" in *UNKNOWN*"no transcripts"*"emergency brake"*) ;; *) errors="$errors B='$b'" ;; esac
case "$a$b" in *"| 0 |"*) errors="$errors zero-instead-of-UNKNOWN" ;; esac

observe "A: session unknown → '$(echo "$a" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')' · B: host without transcripts → '$(echo "$b" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')'${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
