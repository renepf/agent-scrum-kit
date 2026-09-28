#!/usr/bin/env bash
CASE_DESC="every role starts as a real session in parallel: each reads its role, ticks, registers with its own session id and PID, MCP connected, no subagent"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Cost: one model call per role with two role sheets and one tick each (nine roles on 2026-09-14 ~90 s,
# five since the cut of 2026-09-28).
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-start9.XXXXXX")"; trap 'rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K" "$W/out"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
cat >> "$K/kit.env" <<ENV
KIT_REPO="startprobe/projekt"
KIT_WORKTREE_ROOT="$K"
KIT_ISSUE_BACKEND="file"
ENV
# The artefact chain sprint-new.sh has demanded since c750d37: without it no sprint is cut,
# so no session could register. In the real loop the requirements-engineer writes these.
mkdir -p "$K/tickets/1"; for a in intent.md spec.md plan.md; do printf 'live case setup\n' > "$K/tickets/1/$a"; done
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/tickets.sh add-label 1 status:planned \
  && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh startprobe 1 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
ROLES="product-owner requirements-engineer watchdog engineer-a engineer-b engineer-c"
ERWARTET="$(echo "$ROLES" | wc -w | tr -d " ")"
JOBS=""
for r in $ROLES; do
  case "$r" in engineer-*) f=engineer.md ;; *) f="$r.md" ;; esac
  ( cd "$K" && env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color USER="$USER" LANG="${LANG:-de_DE.UTF-8}" KIT_ROLE="$r" \
      claude -p "Read roles/_COMMON.md and roles/$f and take over the role $r. Then run bin/tick.sh. Start no loop and no subagent. Answer in exactly one line: ROLE=$r TICK=<ok|error>." \
      -n "$r" --model claude-opus-5 --settings adapters/claude-code/settings.json --mcp-config .mcp.json --strict-mcp-config \
      --allowed-tools Read "Bash(bin/tick.sh)" "Bash(bin/tick.sh:*)" --max-turns 10 --output-format stream-json --verbose \
      < /dev/null > "$W/out/$r.jsonl" 2> "$W/out/$r.err" ) &
  JOBS="$JOBS $!"
done
# tick.sh removes the anchor of every dead host (tick.sh:43). The sessions end one after
# another, so the last ticks clean up the earlier anchors before this case can read them.
# The anchor is a live artefact: snapshot it while the hosts run.
mkdir -p "$W/anchors"
( while :; do for f in "$K"/.pid-roles/*; do [ -f "$f" ] && cp "$f" "$W/anchors/$(basename "$f")"; done; sleep 0.2; done ) 2>/dev/null &
WATCH=$!
wait $JOBS
kill "$WATCH" 2>/dev/null; wait "$WATCH" 2>/dev/null
out="$(python3 - "$W" <<'PY'
import glob, json, os, sys
W = sys.argv[1]; K = W + "/kit"
rf = glob.glob(K + "/sprints/*/roster.md")
rows = [l for l in open(rf[0]) if l.startswith("| 2")] if rf else []
roster = {l.split("|")[2].strip(): (l.split("|")[3].strip(), l.split("|")[5].strip()) for l in rows}
blocked, bad, pids = [], [], set()
for f in sorted(glob.glob(W + "/out/*.jsonl")):
    role = os.path.basename(f)[:-6]; init = res = None; hook = False
    for line in open(f):
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("type") == "system" and r.get("subtype") == "init": init = r
        if r.get("type") == "system" and r.get("subtype") == "hook_response" and "ROLE ANCHOR" in json.dumps(r): hook = True
        if r.get("type") == "result": res = r
    txt = (res or {}).get("result") or ""
    if not res or any(s in txt for s in ("session limit", "usage limit", "rate limit", "API Error")):
        blocked.append(role); continue
    sid = (init or {}).get("session_id"); rsid, rpid = roster.get(role, ("-", "-")); pids.add(rpid)
    ap = f"{W}/anchors/{rpid}"
    anchor = open(ap).read().strip() if os.path.exists(ap) else None
    mcp = [m["status"] for m in (init or {}).get("mcp_servers", [])]
    checks = {"sid": sid == rsid, "anchor": anchor == role, "hook": hook, "mcp": mcp == ["connected", "connected"],
              "spawned0": (res.get("subagent_stats") or {}).get("spawned") == 0, "tick": f"ROLE={role} TICK=ok" in txt}
    if not all(checks.values()): bad.append(role + ":" + ",".join(k for k, v in checks.items() if not v))
print(f"ROWS {len(rows)}")
print(f"PIDS {len(pids)}")
print("BLOCKED " + " ".join(blocked))
print("BAD " + " ".join(bad))
PY
)"
rows="$(printf '%s' "$out" | sed -n 's/^ROWS //p')"; pids="$(printf '%s' "$out" | sed -n 's/^PIDS //p')"
blocked="$(printf '%s' "$out" | sed -n 's/^BLOCKED //p')"; bad="$(printf '%s' "$out" | sed -n 's/^BAD //p')"
[ -z "$blocked" ] || { echo "OBSERVED: BLOCKED — the host did not answer for:$blocked"; exit 3; }
observe "roster $rows/$ERWARTET · $pids distinct host PIDs · per role session-id=roster, anchor, hook anchor, MCP 2x connected, 0 subagents, TICK=ok${bad:+ · ERRORS: $bad}"
echo "OBSERVED: $OBSERVED"
[ "$rows" = "$ERWARTET" ] && [ "$pids" = "$ERWARTET" ] && [ -z "$bad" ]
