#!/usr/bin/env bash
CASE_DESC="a background session with an inherited role: the hook stays silent, the tick ends with exit 3 without an anchor; a normal child environment stays a role"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'rm -f "$KIT_ROOT/.pid-roles/4711"; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
sed -i '' 's/^KIT_HOST="test-fixture"/KIT_HOST="claude-code"/' "$KIT_ENV_FILE"
H="$KIT_ROOT/adapters/claude-code/session-start.sh"
errors=""
h1="$(printf '{"source":"startup"}' | CLAUDE_CODE_SESSION_KIND=bg KIT_ROLE=engineer-a "$H" 2>&1)"; r1=$?
w1="$(printf '{"source":"startup"}' | CLAUDE_CODE_SESSION_KIND=bg KIT_ROLE=engineer-a KIT_WAKE_DELAY=0 "$H" --wake 2>&1)"; rw=$?
[ -z "$h1" ] && [ "$r1" = 0 ] && [ -z "$w1" ] && [ "$rw" = 0 ] || errors="$errors hook-not-silent"
t1="$(CLAUDE_CODE_SESSION_KIND=bg KIT_ROLE=engineer-a KIT_HOST_PID=4711 KIT_SESSION_ID=bg "$BIN/tick.sh" 2>&1)"; rt=$?
[ "$rt" = 3 ] || errors="$errors tick-exit-$rt"
[ ! -f "$KIT_ROOT/.pid-roles/4711" ] || errors="$errors anchor-written"
# Counter-check: CLAUDE_CODE_CHILD_SESSION=1 stands in every tool environment — that must NOT lock.
h2="$(printf '{"source":"startup"}' | CLAUDE_CODE_CHILD_SESSION=1 KIT_ROLE=engineer-a "$H" 2>&1)"
case "$h2" in *"role **engineer-a**"*) ;; *) errors="$errors child-environment-locked" ;; esac
observe "bg: hook 0 bytes (context and --wake), tick exit $rt, no anchor · CLAUDE_CODE_CHILD_SESSION=1: the hook delivers the role${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
