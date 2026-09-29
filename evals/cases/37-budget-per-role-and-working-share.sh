#!/usr/bin/env bash
CASE_DESC="a per-role threshold and the working share: the scaffolding of the first request does not count"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

# The thresholds of this sandbox, written into kit.env — not into the environment:
# kit.env is read with set -a and overrides the environment.
cat >> "$SANDBOX/kit.env" <<'ENV'
KIT_WARN_TOKENS=250000
KIT_STOP_TOKENS=300000
KIT_WARN_TOKENS_PRODUCT_OWNER=350000
KIT_STOP_TOKENS_PRODUCT_OWNER=400000
KIT_STOP_TOKENS_ENGINEER_C="a lot"
ENV

# Both roles carry the SAME transcript. Only the role decides.
#   sess-warn:  first request 1 100, largest turn 260 000 → working share 258 900
#   sess-floor: first request 260 000, largest turn 262 000 → working share 2 000
{
  printf '# roster\n\n| Time | Role | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | sess-warn | test-fixture |\n'
  printf '| 2026-01-01 00:00 | product-owner | sess-warn | test-fixture |\n'
  printf '| 2026-01-01 00:00 | engineer-b | sess-floor | test-fixture |\n'
  printf '| 2026-01-01 00:00 | engineer-c | sess-warn | test-fixture |\n'
} > "$SPRINT/roster.md"

KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1

field() { grep "| $1 |" "$SPRINT/budget.md" | awk -F'|' -v n="$2" '{gsub(/^ +| +$/,"",$n); print $n}'; }
state_of() { field "$1" 6; }
share_of() { field "$1" 7 | tr -d ' '; }
context_of() { field "$1" 4 | tr -d ' '; }

ea_state="$(state_of engineer-a)"; po_state="$(state_of product-owner)"; eb_state="$(state_of engineer-b)"
ea_share="$(share_of engineer-a)"; eb_share="$(share_of engineer-b)"
eb_context="$(context_of engineer-b)"
stop_line="$(grep -c '^STOP ' "$SPRINT/budget.md")"

errors=""
# 1. the same transcript, two roles: only the engineer warns
case "$ea_state" in warning*) ;; *) errors="$errors engineer-a=$ea_state" ;; esac
[ "$po_state" = "ok" ] || errors="$errors product-owner=$po_state"
# 2. the working share is reported, and it is context minus the first request
[ "$ea_share" = "258900" ] || errors="$errors share-a=$ea_share"
[ "$eb_share" = "2000" ] || errors="$errors share-b=$eb_share"
# 3. a session that is nothing but scaffolding is not reset, although its context is above the warning
[ "$eb_context" = "262000" ] || errors="$errors context-b=$eb_context"
[ "$eb_state" = "ok" ] || errors="$errors engineer-b=$eb_state"
# 4. an unreadable per-role entry falls back to the general threshold, never to 0
ec_state="$(state_of engineer-c)"
case "$ec_state" in warning*) ;; *) errors="$errors engineer-c=$ec_state" ;; esac
# 5. no stop flag anywhere in this fixture
[ "$stop_line" = "0" ] || errors="$errors stop-flags=$stop_line"

observe "engineer-a '$ea_state' · product-owner '$po_state' (same transcript, threshold 350000) · engineer-b context $eb_context share $eb_share '$eb_state' · engineer-c with an unreadable stop threshold '$ec_state' · stop flags $stop_line${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
