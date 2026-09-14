#!/usr/bin/env bash
CASE_DESC="neun echte Sessions starten parallel: jede liest ihre Rolle, tickt, registriert sich mit eigener Session-ID und PID, MCP verbunden, kein Subagent"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Kosten: neun Modellaufrufe mit je zwei Rollenblaettern und einem Tick (am 2026-09-14 ~90 s).
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-start9.XXXXXX")"; trap 'rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K" "$W/out"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
cat >> "$K/kit.env" <<ENV
KIT_REPO="startprobe/projekt"
KIT_WORKTREE_ROOT="$K"
KIT_ISSUE_BACKEND="file"
ENV
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/tickets.sh add-label 1 status:planned \
  && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh startprobe 1 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
ROLES="product-owner simplicity-reviewer watchdog engineer-a engineer-b qa-ruthless security-engineer acceptance-tester merge-gate"
JOBS=""
for r in $ROLES; do
  case "$r" in engineer-*) f=engineer.md ;; *) f="$r.md" ;; esac
  ( cd "$K" && env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color USER="$USER" LANG="${LANG:-de_DE.UTF-8}" KIT_ROLE="$r" \
      claude -p "Lies roles/_COMMON.md und roles/$f und uebernimm die Rolle $r. Fuehre dann bin/tick.sh aus. Starte keinen Loop und keinen Subagenten. Antworte in genau einer Zeile: ROLLE=$r TICK=<ok|fehler>." \
      -n "$r" --model claude-opus-5 --settings adapters/claude-code/settings.json --mcp-config .mcp.json --strict-mcp-config \
      --allowed-tools Read "Bash(bin/tick.sh)" "Bash(bin/tick.sh:*)" --max-turns 10 --output-format stream-json --verbose \
      < /dev/null > "$W/out/$r.jsonl" 2> "$W/out/$r.err" ) &
  JOBS="$JOBS $!"
done
wait $JOBS
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
        if r.get("type") == "system" and r.get("subtype") == "hook_response" and "ROLLENANKER" in json.dumps(r): hook = True
        if r.get("type") == "result": res = r
    txt = (res or {}).get("result") or ""
    if not res or any(s in txt for s in ("session limit", "usage limit", "rate limit", "API Error")):
        blocked.append(role); continue
    sid = (init or {}).get("session_id"); rsid, rpid = roster.get(role, ("-", "-")); pids.add(rpid)
    anchor = open(f"{K}/.pid-roles/{rpid}").read().strip() if os.path.exists(f"{K}/.pid-roles/{rpid}") else None
    mcp = [m["status"] for m in (init or {}).get("mcp_servers", [])]
    checks = {"sid": sid == rsid, "anker": anchor == role, "hook": hook, "mcp": mcp == ["connected", "connected"],
              "spawned0": (res.get("subagent_stats") or {}).get("spawned") == 0, "tick": f"ROLLE={role} TICK=ok" in txt}
    if not all(checks.values()): bad.append(role + ":" + ",".join(k for k, v in checks.items() if not v))
print(f"ROWS {len(rows)}")
print(f"PIDS {len(pids)}")
print("BLOCKED " + " ".join(blocked))
print("BAD " + " ".join(bad))
PY
)"
rows="$(printf '%s' "$out" | sed -n 's/^ROWS //p')"; pids="$(printf '%s' "$out" | sed -n 's/^PIDS //p')"
blocked="$(printf '%s' "$out" | sed -n 's/^BLOCKED //p')"; bad="$(printf '%s' "$out" | sed -n 's/^BAD //p')"
[ -z "$blocked" ] || { echo "BEOBACHTET: BLOCKIERT — Host antwortete nicht fuer:$blocked"; exit 3; }
observe "roster $rows/9 · $pids verschiedene Host-PIDs · je Rolle Session-ID=Roster, Anker, Hook-Anker, MCP 2x connected, 0 Subagenten, TICK=ok${bad:+ · FEHLER: $bad}"
echo "BEOBACHTET: $OBSERVED"
[ "$rows" = 9 ] && [ "$pids" = 9 ] && [ -z "$bad" ]
