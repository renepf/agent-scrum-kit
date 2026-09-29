#!/usr/bin/env bash
# Amnesia gates for the shared wiki (protocols/LIBRARIAN.md section 4). One script, three modes:
#   wiki-hook.sh seed      S1  SessionStart:      the seed lands in `messages`, never in tools or system
#   wiki-hook.sh gate      S2  PreToolUse:        Edit|Write under WIKI_GATE_PATHS is denied until a query receipt exists
#   wiki-hook.sh receipt   S3  PostToolUse (Bash): a `wiki.sh query` command writes the receipt for the session
# Silent (exit 0) when WIKI_ROOT is unset, so sessions without a wiki notice nothing.
#   WIKI_GATE_PATHS  colon-separated path prefixes the gate guards (unset: the gate allows everything)
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
W="$KIT_ROOT/bin/wiki.sh"
INPUT="$(cat 2>/dev/null || true)"
[ -n "${WIKI_ROOT:-}" ] && [ -d "$WIKI_ROOT" ] || exit 0
field() { printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin); v = d
    for k in sys.argv[1].split("."): v = v.get(k, "") if isinstance(v, dict) else ""
    print(v)
except Exception: print("")' "$1"; }
SID="$(field session_id)"

case "${1:-}" in
  seed)
    python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$("$W" seed)"
    ;;
  gate)
    P="$(field tool_input.file_path)"
    [ -n "$P" ] && [ -n "${WIKI_GATE_PATHS:-}" ] || exit 0
    hit=""; IFS=:; for g in $WIKI_GATE_PATHS; do case "$P" in "$g"*) hit=1 ;; esac; done; unset IFS
    [ -n "$hit" ] || exit 0
    [ -n "$SID" ] || exit 0
    "$W" gate "$SID"
    ;;
  receipt)
    C="$(field tool_input.command)"
    case "$C" in *"wiki.sh query"*) [ -n "$SID" ] && "$W" receipt "$SID" ;; esac
    exit 0
    ;;
  *) echo "usage: wiki-hook.sh {seed|gate|receipt}" >&2; exit 64 ;;
esac
