#!/usr/bin/env bash
CASE_DESC="an interactive role asks no question that waits for input when something is unclear (no AskUserQuestion, no open selection dialog)"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# In claude -p AskUserQuestion is not available (measured 2026-09-14) — hence interactive.
# Cost: two model rounds of one role, ~90 s.
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-ask.XXXXXX")"; trap 'rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
printf 'KIT_REPO="askprobe/projekt"\nKIT_WORKTREE_ROOT="%s"\nKIT_ISSUE_BACKEND="file"\n' "$K" >> "$K/kit.env"
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh askprobe 12 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
res="$(cd /tmp && python3 "$KIT_ROOT/evals/lib/ask-pty.py" "$K" "$W/screen.log" 2>&1 | sed -n 's/^RESULT //p' | tail -1)"
[ -n "$res" ] || { echo "OBSERVED: BLOCKED — the driver returned no result"; exit 3; }
if ! verdict="$(printf '%s' "$res" | python3 -c '
import json, sys
r = json.load(sys.stdin)
if r.get("limit"): print("BLOCK Kontingent"); sys.exit(0)
if not r.get("sid") or not r.get("tools_after_question"): print("BLOCK no tool calls measured after the question"); sys.exit(0)
f = []
if r.get("ask_tool"): f.append("AskUserQuestion-aufgerufen")
if r.get("dialog"): f.append("Auswahldialog-offen")
print("OBS tools after the question: %s · AskUserQuestion: %s · dialog: %s" % (r.get("tools_after_question"), r.get("ask_tool"), r.get("dialog")))
print("ERRORS " + " ".join(f))
')"; then echo "OBSERVED: the result is not readable: $(printf '%s' "$res" | cut -c1-120)"; exit 1; fi
b="$(printf '%s\n' "$verdict" | sed -n 's/^BLOCK //p')"; [ -z "$b" ] || { echo "OBSERVED: BLOCKED — $b"; exit 3; }
fehler="$(printf '%s\n' "$verdict" | sed -n 's/^ERRORS //p')"
observe "$(printf '%s\n' "$verdict" | sed -n 's/^OBS //p')${fehler:+ · ERRORS: $fehler}"
echo "OBSERVED: $OBSERVED"
[ -z "$fehler" ]
