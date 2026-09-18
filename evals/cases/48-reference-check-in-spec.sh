#!/usr/bin/env bash
CASE_DESC="with a reference configured, planned demands a REFERENCE line in the spec.md; without one the kit demands nothing; the role names the reference and the requirements source"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; wrong=0; errors=""
fail() { wrong=$((wrong + 1)); errors="$errors $*"; }
check() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tr '\n' ' ' | head -c 120)'" ;; esac; }
plan() { KIT_ROLE=product-owner "$BIN/status.sh" 8 planned "Verdict: ok" 2>&1; }
ref() { sed -i.bak '/^KIT_REFERENCE_CMD=/d' "$SANDBOX/kit.env"; [ -z "$1" ] || echo "KIT_REFERENCE_CMD=\"$1\"" >> "$SANDBOX/kit.env"; }

sandbox_plannable 8
printf 'Behaviour: one file per run\n' > "$SANDBOX/tickets/8/spec.md"

# 1. A reference configured, the spec.md without evidence: refused, nothing written.
ref "echo referenz-lauf"
s1="$(sandbox_snap 8)"; out="$(plan)"; s2="$(sandbox_snap 8)"
check a-without-REFERENCE "$out" '*planned rejected*REFERENCE*'
n=$((n + 1)); [ "$s1" = "$s2" ] || fail "a-state-changed"

# 2. With the evidence in the spec.md it passes.
printf 'Behaviour: one file per run\n\nREFERENCE: reference run 2026-09-17 11:20, the export creates a file\n' > "$SANDBOX/tickets/8/spec.md"
out="$(plan)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "b-with-REFERENCE-rejected:'$(printf '%s' "$out" | tail -1 | head -c 110)'"

# 3. Without a configured reference the kit demands no evidence.
sandbox_plannable 9 "src/m9/**"
printf 'Behaviour: without a reference\n' > "$SANDBOX/tickets/9/spec.md"
ref ""
out="$(KIT_ROLE=product-owner "$BIN/status.sh" 9 planned "Verdict: ok" 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "c-without-reference-rejected:'$(printf '%s' "$out" | tail -1 | head -c 110)'"

# 4. The role sheet and the example configuration name both keys.
RE="$KIT_ROOT/roles/requirements-engineer.md"
n=$((n + 1)); grep -q 'KIT_REFERENCE_CMD' "$RE" || fail "d-role-without-reference-command"
n=$((n + 1)); grep -q 'KIT_REQUIREMENTS_DIR' "$RE" || fail "e-role-without-requirements-source"
n=$((n + 1)); grep -q '^KIT_REFERENCE_CMD=' "$KIT_ROOT/kit.env.example" || fail "f-kit.env.example-without-reference-command"
n=$((n + 1)); grep -q '^KIT_REQUIREMENTS_DIR=' "$KIT_ROOT/kit.env.example" || fail "g-kit.env.example-without-requirements-source"
# The role runs the check itself, in its own session (the iron rule).
n=$((n + 1)); grep -q 'in your own session' "$RE" || fail "h-role-does-not-say-own-session"

observe "$n checks, $wrong wrong${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ "$wrong" = 0 ]
