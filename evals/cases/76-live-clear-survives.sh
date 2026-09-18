#!/usr/bin/env bash
CASE_DESC="an interactive session starts into its role without input and survives /clear: a new session id, the same PID, registration again and a tick without input"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Cost: two model rounds of one role (start, after /clear); on 2026-09-14 ~65 s.
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-clear.XXXXXX")"; trap 'rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
cat >> "$K/kit.env" <<ENV
KIT_REPO="clearprobe/projekt"
KIT_WORKTREE_ROOT="$K"
KIT_ISSUE_BACKEND="file"
ENV
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh clearprobe 9 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
res="$(python3 "$KIT_ROOT/evals/lib/clear-pty.py" "$K" "$W/screen.txt" 2>&1 | sed -n 's/^RESULT //p' | tail -1)"
[ -n "$res" ] || { echo "OBSERVED: BLOCKED — the driver returned no result"; exit 3; }
grep -qiE 'session limit|usage limit|rate limit' "$W/screen.txt" && { echo "OBSERVED: BLOCKED — Kontingent"; exit 3; }
# Display and check in ONE call, and tight: if the result cannot be read,
# python ends with exit != 0 and the case fails. Before, the display ran empty on a quoting
# error, and an unreadable answer would have counted as "no errors".
if ! verdict="$(printf '%s' "$res" | python3 -c '
import json, sys
r = json.load(sys.stdin)
need = {"start_ok": True, "clear_new_id": True, "clear_registered_again": True, "sid1_transcript": True, "sid2_transcript": True}
f = [k for k, v in need.items() if r.get(k) is not v]
if not r.get("sid1") or r.get("sid1") == r.get("sid2"): f.append("session-id-unchanged")
if (r.get("tick_calls_after_clear") or 0) < 1: f.append("no-tick-after-clear")
print("OBS start without input: %s · /clear: %s -> %s · registered again: %s · tick after /clear: %s" % (
    r.get("start_ok"), str(r.get("sid1"))[:8], str(r.get("sid2"))[:8], r.get("clear_registered_again"), r.get("tick_calls_after_clear")))
print("ERRORS " + " ".join(f))
')"; then
  echo "OBSERVED: the driver's result is not readable: $(printf '%s' "$res" | cut -c1-120)"
  exit 1
fi
fehler="$(printf '%s\n' "$verdict" | sed -n 's/^ERRORS //p')"
observe "$(printf '%s\n' "$verdict" | sed -n 's/^OBS //p')${fehler:+ · ERRORS: $fehler}"
echo "OBSERVED: $OBSERVED"
[ -z "$fehler" ]
