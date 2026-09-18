#!/usr/bin/env bash
CASE_DESC="planned demands the artefact chain intent.md, spec.md, plan.md per ticket; every missing or empty link is named on its own, a rejection writes nothing; the requirements-engineer is in the cast and picks up backlog"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 110)'" ;; esac; }
plan() { KIT_ROLE=product-owner "$BIN/status.sh" 7 planned "Verdict: ok" 2>&1; }
art() { printf '%s\n' "${2-content}" > "$SANDBOX/tickets/7/$1"; }   # ${2-...}: an empty string stays empty
rejected() {
  local s1 s2 out
  s1="$(sandbox_snap 7)"; out="$(plan)"; s2="$(sandbox_snap 7)"
  expect "$1" "$out" "$2"
  [ "$s1" = "$s2" ] || fail "$1:state-changed"
}

sandbox_plannable 7
rm -f "$SANDBOX/tickets/7/intent.md" "$SANDBOX/tickets/7/spec.md" "$SANDBOX/tickets/7/plan.md"

# The chain is named link by link, not as one collective message: intent.md first.
rejected a-without-intent '*planned rejected*intent.md*'
art intent.md "Problem: the export is missing"
rejected b-without-spec '*planned rejected*spec.md*'
art spec.md "Behaviour: one file per run"
rejected c-without-plan '*planned rejected*plan.md*'
# An empty file is not an artefact.
art plan.md ""
rejected d-plan-empty '*planned rejected*plan.md*'

art plan.md "Steps: 1. the module, 2. the test"
out="$(plan)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "e-complete-rejected:'$(printf '%s' "$out" | tail -1 | head -c 110)'"
n=$((n + 1)); case "$(sandbox_labels 7)" in *"status:planned"*) ;; *) fail "e-no-label:'$(sandbox_labels 7)'" ;; esac

# Wiring: the role exists, stands in the cast and picks up backlog.
n=$((n + 1)); [ -f "$KIT_ROOT/roles/requirements-engineer.md" ] || fail "f-role-file-missing"
n=$((n + 1)); grep -q '^KIT_ROLES=.*requirements-engineer' "$KIT_ROOT/kit.env.example" || fail "g-not-in-KIT_ROLES"
n=$((n + 1)); grep -q '^requirements-engineer|backlog' "$KIT_ROOT/kit.env.example" || fail "h-no-queue"
n=$((n + 1)); grep -q 'requirements-engineer' "$KIT_ROOT/protocols/LOOP.md" || fail "i-not-in-the-cast-of-the-protocol"

observe "$n checks, $wrong wrong${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ "$wrong" = 0 ]
