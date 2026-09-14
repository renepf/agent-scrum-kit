#!/usr/bin/env bash
CASE_DESC="SessionStart-Hook: still ohne Rolle; mit Anker Rollenauftrag; --wake weckt nur bei startup, clear, resume"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
H="$KIT_ROOT/adapters/claude-code/session-start.sh"
PIDF="$KIT_ROOT/.pid-roles/$$"
trap 'rm -f "$PIDF"' EXIT
fehler=""
hook() { printf '{"source":"%s"}' "$1" | env -u KIT_ROLE KIT_HOST_PID=$$ KIT_WAKE_DELAY=0 "$H" ${2:-}; }

rm -f "$PIDF"
o0="$(hook startup 2>&1)"; r0=$?
[ -z "$o0" ] && [ "$r0" = 0 ] || fehler="$fehler ohne-Rolle-nicht-still"

mkdir -p "$KIT_ROOT/.pid-roles"; echo engineer-b > "$PIDF"
o1="$(hook clear 2>/dev/null)"; r1=$?
ctx="$(printf '%s' "$o1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"
case "$ctx" in *"Rolle **engineer-b**"*"roles/engineer.md"*"/loop 5m"*) ;; *) fehler="$fehler kontext-falsch" ;; esac

wake=""
for s in startup clear resume compact fork; do
  e="$(hook "$s" --wake 2>&1 >/dev/null)"; r=$?
  wake="$wake $s:$r"
  case "$s" in
    startup|clear|resume) [ "$r" = 2 ] && case "$e" in *"engineer-b"*) true ;; *) false ;; esac || fehler="$fehler wake-$s" ;;
    compact|fork) [ "$r" = 0 ] && [ -z "$e" ] || fehler="$fehler still-$s" ;;
  esac
done
observe "ohne Rolle: Exit $r0, 0 Bytes · Anker engineer-b + clear: additionalContext mit roles/engineer.md und /loop 5m · --wake Exitcodes:$wake${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
