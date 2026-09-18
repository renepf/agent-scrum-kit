#!/usr/bin/env bash
CASE_DESC="a real restart under role-loop.sh: the role calls restart-self.sh, the loop starts claude again, the new session registers without input, the stop file ends the loop"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Cost: two model sessions of one role; on 2026-09-14 ~100 s. A clean environment (the driver).
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-restart.XXXXXX")"; trap 'pkill -f "role-loop.sh engineer-a" 2>/dev/null; rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
printf 'KIT_REPO="restartprobe/projekt"\nKIT_WORKTREE_ROOT="%s"\nKIT_ISSUE_BACKEND="file"\n' "$K" >> "$K/kit.env"
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh restartprobe 9 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
res="$(cd /tmp && python3 "$KIT_ROOT/evals/lib/restart-pty.py" "$K" "$W/screen.log" 2>&1 | sed -n 's/^RESULT //p' | tail -1)"
[ -n "$res" ] || { echo "OBSERVED: BLOCKED — the driver returned no result"; exit 3; }
grep -qiE 'session limit|usage limit|rate limit' "$W/screen.log" && { echo "OBSERVED: BLOCKED — Kontingent"; exit 3; }
# Display and check in one call; an unreadable result fails.
if ! verdict="$(printf '%s' "$res" | python3 -c '
import json, sys
r = json.load(sys.stdin)
f = []
for k in ("start1", "old_ended", "registered_again", "loop_ends_on_stop", "restart_in_chat"):
    if r.get(k) is not True: f.append(k)
if not r.get("pid1") or r.get("pid1") == r.get("pid2"): f.append("pid-unchanged")
if not r.get("sid1") or r.get("sid1") == r.get("sid2"): f.append("session-id-unchanged")
if r.get("reg2") != r.get("sid2"): f.append("registry-weicht-ab")
if r.get("anchor2") != "engineer-a": f.append("anker")
if (r.get("starts_in_log") or 0) < 2: f.append("no-second-start-in-the-log")
print("OBS PID %s -> %s · session %s -> %s · starts in the log %s · the stop ended the loop: %s" % (
    r.get("pid1"), r.get("pid2"), str(r.get("sid1"))[:8], str(r.get("sid2"))[:8], r.get("starts_in_log"), r.get("loop_ends_on_stop")))
print("ERRORS " + " ".join(f))
')"; then
  echo "OBSERVED: the driver's result is not readable: $(printf '%s' "$res" | cut -c1-120)"; exit 1
fi
fehler="$(printf '%s\n' "$verdict" | sed -n 's/^ERRORS //p')"
observe "$(printf '%s\n' "$verdict" | sed -n 's/^OBS //p')${fehler:+ · ERRORS: $fehler}"
echo "OBSERVED: $OBSERVED"
[ -z "$fehler" ]
