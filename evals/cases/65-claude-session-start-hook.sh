#!/usr/bin/env bash
CASE_DESC="the SessionStart hook: silent without a role; with an anchor the role assignment; --wake wakes only on startup, clear, resume"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
H="$KIT_ROOT/adapters/claude-code/session-start.sh"
PIDF="$KIT_ROOT/.pid-roles/$$"
trap 'rm -f "$PIDF"' EXIT
errors=""
hook() { printf '{"source":"%s"}' "$1" | env -u KIT_ROLE KIT_HOST_PID=$$ KIT_WAKE_DELAY=0 "$H" ${2:-}; }

rm -f "$PIDF"
o0="$(hook startup 2>&1)"; r0=$?
[ -z "$o0" ] && [ "$r0" = 0 ] || errors="$errors without-a-role-not-silent"

mkdir -p "$KIT_ROOT/.pid-roles"; echo engineer-b > "$PIDF"
o1="$(hook clear 2>/dev/null)"; r1=$?
ctx="$(printf '%s' "$o1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"
case "$ctx" in *"role **engineer-b**"*"roles/engineer.md"*"/loop 5m"*) ;; *) errors="$errors context-wrong" ;; esac

wake=""
for s in startup clear resume compact fork; do
  e="$(hook "$s" --wake 2>&1 >/dev/null)"; r=$?
  wake="$wake $s:$r"
  case "$s" in
    startup|clear|resume) [ "$r" = 2 ] && case "$e" in *"engineer-b"*) true ;; *) false ;; esac || errors="$errors wake-$s" ;;
    compact|fork) [ "$r" = 0 ] && [ -z "$e" ] || errors="$errors still-$s" ;;
  esac
done
observe "without a role: exit $r0, 0 bytes · the anchor engineer-b + clear: additionalContext with roles/engineer.md and /loop 5m · --wake exit codes:$wake${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
