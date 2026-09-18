#!/usr/bin/env bash
CASE_DESC="the thresholds fire at the right place, the boundary value included"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

{
  printf '# roster\n\n| Time | Role | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | sess-quiet | test-fixture |\n'
  printf '| 2026-01-01 00:00 | engineer-b | sess-warn | test-fixture |\n'
  printf '| 2026-01-01 00:00 | qa-ruthless | sess-stop | test-fixture |\n'
} > "$SPRINT/roster.md"

KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
state_of() { grep "| $1 |" "$SPRINT/budget.md" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}'; }

lq="$(state_of engineer-a)"; lw="$(state_of engineer-b)"; ls_="$(state_of qa-ruthless)"
stop_line="$(grep '^STOP ' "$SPRINT/budget.md" | tr '\n' ' ')"

errors=""
[ "$lq" = "ok" ] || errors="$errors engineer-a=$lq"
case "$lw" in warning*) ;; *) errors="$errors engineer-b=$lw" ;; esac
case "$ls_" in *STOP*) ;; *) errors="$errors qa-ruthless=$ls_" ;; esac
[ "$stop_line" = "STOP qa-ruthless " ] || errors="$errors flag='$stop_line'"

observe "1150→ok · 260000→warning · 300010→STOP · flag line '$(echo "$stop_line" | sed 's/ $//')'${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
