#!/usr/bin/env bash
CASE_DESC="a fresh copy runs once the configuration is filled in"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

TARGET="$(mktemp -d "${TMPDIR:-/tmp}/kit-copy.XXXXXX")"
trap 'rm -rf "$TARGET"' EXIT
# The way another project would copy the kit: without .git, without kit.env.
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude 'sprints' --exclude 'tickets' -cf - . ) | ( cd "$TARGET" && tar -xf - )

errors=""

# 1. Without kit.env nothing runs, and the message says what to do.
out="$(cd "$TARGET" && KIT_ENV_FILE="$TARGET/kit.env" bin/preflight.sh 2>&1)"; rc=$?
[ "$rc" != 0 ] || errors="$errors runs-without-kit.env"
case "$out" in *"kit.env.example"*) ;; *) errors="$errors message-does-not-name-the-next-step" ;; esac

# 2. Fill in the configuration — exactly the way the README describes.
cp "$TARGET/kit.env.example" "$TARGET/kit.env"
python3 - "$TARGET" <<'PY'
import sys, pathlib
z = pathlib.Path(sys.argv[1])
p = z / "kit.env"
t = p.read_text()
t = t.replace('KIT_REPO="UNKNOWN — ask the owner, e.g. my-org/my-repo"', 'KIT_REPO="fremd/projekt"')
t = t.replace('KIT_WORKTREE_ROOT="$HOME/Developer/my-project"', f'KIT_WORKTREE_ROOT="{z}"')
t = t.replace('KIT_ISSUE_BACKEND="gh"', 'KIT_ISSUE_BACKEND="file"')
t += f'\nKIT_SPRINTS_DIR="{z}/sprints"\nKIT_MEMORY_DIR="{z}/memory"\n'
p.write_text(t)
PY

# 3. The full path: preflight, sprint, ticket, status change, chat, index.
( cd "$TARGET" && export KIT_ROLE=product-owner KIT_SESSION_ID=kopie-test KIT_HOST_PID=$$
  unset KIT_BOARD_ENV_FILE
  bin/preflight.sh > /dev/null 2>&1 || exit 11
  bin/tickets.sh add-label 1 status:backlog > /dev/null 2>&1 || exit 12
  # Vor planned: AC im Issue, Gate im Ledger (protocols/LOOP.md, Gate-Ledger).
  python3 -c 'import json; p=".kit-issues.json"; db=json.load(open(p)); db["1"]["body"]="AC-1: the fresh copy runs"; json.dump(db, open(p, "w"))' || exit 12
  mkdir -p tickets/1 && printf '# Gates: #1\n\nOWNS: src/**\n\n- [ ] AC-1: the fresh copy runs\n  CHECK: bin/preflight.sh\n  EXPECT: preflight ok\n  EVIDENCE: pending\n' > tickets/1/GATES.md || exit 12
  # The artefact chain planned demands (case 46): in the real loop the requirements-engineer writes it.
  for a in intent.md spec.md plan.md; do printf 'Evidence from case 44.\n' > "tickets/1/$a" || exit 12; done
  bin/sprint-new.sh erster-sprint 1 > /dev/null 2>&1 || exit 13
  bin/status.sh 1 planned "los" > /dev/null 2>&1 || exit 14
  bin/say.sh "#1 · the copy runs" <<'EOF' > /dev/null 2>&1 || exit 15
Evidence from the fresh copy.
EOF
  bin/tick.sh > /dev/null 2>&1 || exit 16
  bin/brain.sh note copy-runs "a fresh copy is runnable" <<<'Measured in eval 44.' > /dev/null 2>&1 || exit 17
) ; step=$?
[ "$step" = 0 ] || errors="$errors aborted-at-step-$step"

entries="$(grep -c '^| [0-9]' "$TARGET/sprints/$(cat "$TARGET/sprints/CURRENT" 2>/dev/null)/INDEX.md" 2>/dev/null || echo 0)"
[ "$entries" -ge 2 ] || errors="$errors index-has-only-$entries-entries"

observe "without kit.env: exit $rc with a hint · after filling it in: preflight, sprint, status change, chat, tick, memory, an index with $entries entries${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
