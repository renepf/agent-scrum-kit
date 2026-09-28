#!/usr/bin/env bash
# One round of situational awareness. EVERY role calls this at the start of EVERY loop round.
#
#   export KIT_ROLE=engineer-a
#   bin/tick.sh
#
# Idempotent. In this order:
#   1. register and renew the twin lock — a new session id pulls the memory back
#   2. rejections first (engineers only): they come before any new ticket
#   3. your own tickets, then free tickets from your own queue
#   4. unseen chat entries and mentions @<role> — each exactly once
#   5. token state, STOP flag
# Without an active sprint it ends with exit 0 — a waiting role is not an error.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# --signal: exit 4 when nothing is waiting for this role. Without the flag it stays 0 —
# existing callers and humans should not see a new error code. The watchdog loop uses it to ask
# whether a model start is worth it: a tick costs nothing, an empty round costs a context window.
SIGNAL=0
[ "${1:-}" = "--signal" ] && SIGNAL=1
WORK=0

R="$(role)"
if [ ! -s "$CURRENT_FILE" ]; then
  echo "[$R] no active sprint. The product-owner cuts one with bin/sprint-new.sh. Nothing to do."
  exit 0
fi

SPRINT="$(sprint_dir)"
SID="$(session_id)"
STATE="$SPRINT/.tick-$R"
P="$KIT_LABEL_PREFIX"; O="$KIT_OWNER_PREFIX"

# Background session: it inherited KIT_ROLE but is not a role — no anchor, no tick.
BG="$KIT_ROOT/adapters/$KIT_HOST/is-background.sh"
if [ -x "$BG" ] && "$BG"; then
  echo "[$R] background session — no role, no tick. Do nothing."
  exit 3
fi

# Clear away anchors of dead or reassigned PIDs. Otherwise the twin lock mistakes a foreign
# process for a running role.
for f in "$PID_ROLES"/*; do
  [ -f "$f" ] || continue
  host_alive "$(basename "$f")" || rm -f "$f"
done

# Role anchor on EVERY tick — not only on a new registration. Otherwise it is missing exactly when
# it is needed: after the first context reset.
anchor_role "$R"

# --- 1. registration + twin lock ---------------------------------------------
NEW_SESSION=0
grep -q "| $R | $SID |" "$SPRINT/roster.md" 2>/dev/null || NEW_SESSION=1
"$BIN_DIR/register.sh" "$SID" > /dev/null   # aborts when a twin is running
if [ "$NEW_SESSION" = 1 ]; then
  echo "[$R] new session $SID — pulling the memory back (bin/brain.sh recall):"
  "$BIN_DIR/brain.sh" recall
fi

# --- 2./3. tickets -----------------------------------------------------------
QUEUE="$(printf '%s\n' "$KIT_QUEUE_MAP" | grep "^$R|" | cut -d'|' -f2 || true)"
if [ -z "$QUEUE" ]; then
  echo "[$R] takes no tickets."
else
  "$BIN_DIR/preflight.sh" > /dev/null 2>&1 || { echo "[$R] preflight FAILED — stop and report, do not guess." >&2; exit 1; }
  SPRINT_JSON="$("$BIN_DIR/tickets.sh" sprint)" || { echo "[$R] ticket list not readable — a failure, not an empty sprint." >&2; exit 1; }

  # Rejection: owner:<engineer> in in-progress, last status change NOT by the engineer itself.
  case "$R" in
    engineer-*)
      IP="$(board_name in-progress)"
      for n in $(printf '%s' "$SPRINT_JSON" | python3 -c '
import json, sys
p, o = sys.argv[1], sys.argv[2]
for i in json.load(sys.stdin):
    names = [l["name"] for l in i["labels"]]
    if p + "in-progress" in names and o in names:
        print(i["number"])
' "$P" "$O$R"); do
        REJECTED="$("$BIN_DIR/tickets.sh" comments "$n" | python3 -c '
import json, re, sys
me, n, ip = sys.argv[1], sys.argv[2], sys.argv[3]
# A rejection is the in-progress comment that names YOU as the owner and someone else as the sender:
# "**In progress** — engineer-c (sent back by engineer-a)". Before 2026-09-29 the comment named the
# acting role, and the tick read "someone other than me" as the rejection — that broke the moment
# the comment started naming the owner, which the four-eyes gate needs.
heads = [(m.group(1), m.group(2), m.group(3), b) for b in json.load(sys.stdin)
         for m in [re.match(r"^\*\*([^*]+)\*\* — ([a-z-]+)(?: \(sent back by ([a-z-]+)\))? ", b)] if m]
if heads and heads[-1][0] == ip and heads[-1][2] and heads[-1][2] != me:
    note = heads[-1][3].split("\n", 2)[-1].strip()
    print(f"↩ #{n} REJECTED by {heads[-1][2]} — comes before any new ticket:")
    print(f"    {note[:160]}")
    print(f"    Read the finding, fix it, push, then status.sh {n} rfr. Old PASS verdicts do not hold for the new HEAD.")
' "$R" "$n" "$IP")"
        [ -z "$REJECTED" ] || { printf '%s\n' "$REJECTED"; WORK=1; }
      done
      ;;
  esac

  echo "── your queue ($QUEUE) ──"
  if printf '%s' "$SPRINT_JSON" | QUEUE="$QUEUE" python3 -c '
import json, os, sys
p, o, role = sys.argv[1], sys.argv[2], sys.argv[3]
want = os.environ["QUEUE"].split(",")
mine, free = [], []
for i in json.load(sys.stdin):
    names = [l["name"] for l in i["labels"]]
    st = next((l[len(p):] for l in names if l.startswith(p)), "backlog")
    owners = ",".join(l[len(o):] for l in names if l.startswith(o)) or "free"
    line = "  #%-5s [%-11s] %-22s %s" % (i["number"], st, owners, i["title"][:50])
    if o + role in names:
        mine.append(line)
    elif "*" in want or st in want:
        free.append(line)
print("  yours:"); print("\n".join(mine) if mine else "    (none)")
print("  free for you (" + ",".join(want) + "):"); print("\n".join(free) if free else "    (nothing — end the round)")
sys.exit(0 if (mine or free) else 4)
' "$P" "$O" "$R"; then WORK=1; fi
fi

# --- 3b. backlog without the artefact chain -----------------------------------
# Whoever takes backlog (requirements-engineer) or sees everything (product-owner) sees here which
# ticket is still missing a link. planned and sprint-new.sh reject exactly these tickets.
case ",$QUEUE," in
  *,backlog,*|*"*"*)
    GAPS=""
    for b in $("$BIN_DIR/tickets.sh" list "${P}backlog" 2>/dev/null); do
      missing=""
      for a in intent.md spec.md plan.md; do
        grep -q '[^[:space:]]' "$TICKETS_DIR/$b/$a" 2>/dev/null || missing="$missing $a"
      done
      [ -n "$missing" ] && GAPS="$GAPS  #$b missing:$missing
"
    done
    if [ -n "$GAPS" ]; then
      echo "── backlog without the artefact chain (this is how sprint-new.sh and planned reject) ──"
      printf '%s' "$GAPS"
      WORK=1
    fi
    ;;
esac

# --- 3c. kanban: only the product-owner plans, only they see the numbers -------
if [ "$R" = "product-owner" ] && [ -n "${SPRINT_JSON:-}" ]; then
  if printf '%s' "$SPRINT_JSON" | MIN="${KIT_MIN_PLANNED:-7}" STOP="${KIT_QUEUE_STOP:-2}" \
    ENG="$(printf '%s\n' $KIT_ROLES | grep -c '^engineer-')" python3 -c '
import json, os, sys
p = sys.argv[1]
mn, stop, eng = int(os.environ["MIN"]), int(os.environ["STOP"]), int(os.environ["ENG"])
c = {}
for i in json.load(sys.stdin):
    names = [l["name"] for l in i["labels"]]
    st = next((l[len(p):] for l in names if l.startswith(p)), "backlog")
    c[st] = c.get(st, 0) + 1
planned, wip = c.get("planned", 0), c.get("in-progress", 0)
review = c.get("rfr", 0) + c.get("in-review", 0)
test = c.get("rft", 0) + c.get("in-testing", 0)
print("── kanban ──")
print("  planned %d (target at least %d) · in progress %d (engineers %d) · review queue %d · test queue %d"
      % (planned, mn, wip, eng, review, test))
if review > stop or test > stop:
    print("  planning stop: review or test queue above %d. Plan nothing new until it drops to %d." % (stop, stop))
elif planned < mn:
    print("  too little planned: %d instead of %d — cut more, or the team runs dry." % (planned, mn))
hint = review > stop or test > stop or planned < mn or wip < eng
if wip < eng:
    print("  %d engineer(s) without a ticket: take a free planned ticket, otherwise an unblocked one." % (eng - wip))
sys.exit(0 if hint else 4)
' "$P"; then WORK=1; fi
fi

# --- 4. chat: unseen entries and direct mentions, each exactly once --------------
# What is remembered are the seen file:line references, not a line count. A number
# fails as soon as two entries carry the same minute: the index then sorts by
# file name, and a new entry can land before an old one.
[ -f "$SPRINT/INDEX.md" ] || "$BIN_DIR/reindex.sh" > /dev/null || die "reindex.sh failed — tick aborted, not silently continued"
SEEN="$SPRINT/.tick-$R"
if with_lock "$SEEN.lock" python3 - "$SPRINT" "$R" "$SEEN" <<'PY2'
import os, re, sys
sprint, role, seen_path = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
for line in open(os.path.join(sprint, "INDEX.md"), encoding="utf-8"):
    m = re.search(r"\| (chat/[a-z0-9-]+\.md:\d+) \|\s*$", line)
    if m:
        rows.append((m.group(1), line.rstrip("\n")))
seen = set()
if os.path.exists(seen_path):
    seen = {l.strip() for l in open(seen_path, encoding="utf-8") if l.strip()}
new = [(ref, row) for ref, row in rows if ref not in seen]
if not new:
    print(f"[{role}] no new chat entries.")
else:
    print(f"── new in the chat since your last tick ({len(new)}) ──")
    for _, row in new:
        print(row)
# Direct mention: only in NEW entries of other roles. Shown once, never again.
mention = re.compile(r"@" + re.escape(role) + r"(?![a-z0-9-])")
hits = []
for ref, _ in new:
    fname, start = ref.rsplit(":", 1)
    if fname == f"chat/{role}.md":
        continue
    lines = open(os.path.join(sprint, fname), encoding="utf-8").read().split("\n")
    i = int(start) - 1
    body = [lines[i]]
    for l in lines[i + 1:]:
        if re.match(r"^## \d{4}-\d{2}-\d{2} \d{2}:\d{2} · ", l):
            break
        body.append(l)
    if any(mention.search(l) for l in body):
        hits.append((ref, body[0][3:]))
if hits:
    print("── addressed directly to you ──")
    for ref, head in hits:
        print(f"  {ref}  {head}")
tmp = seen_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("\n".join(sorted(seen | {ref for ref, _ in rows})) + "\n")
os.replace(tmp, seen_path)
# One new chat line alone does not justify a model start — otherwise every status change wakes
# the whole team for one line. Addressed directly to you (@role) does.
sys.exit(0 if hits else 4)
PY2
then WORK=1; fi

# --- 5. budget ---------------------------------------------------------------
if [ -f "$SPRINT/budget.md" ]; then
  MINE="$(grep "^| $R |" "$SPRINT/budget.md" || true)"
  [ -z "$MINE" ] || { echo "── your budget ──"; echo "$MINE"; }
  case "$MINE" in *warning*) echo "  Warning: take no new ticket. Do NOT end your loop — keep ticking."; WORK=1 ;; esac
  if grep -q "^STOP $R\$" "$SPRINT/budget.md"; then
    WORK=1
    if [ "${KIT_ROLE_LOOP:-}" = "1" ]; then
      echo "  ⚠ STOP: brain.sh handover (every held #<nr> with state, SHA, next step), then bin/restart-self.sh stop — the watchdog loop starts you fresh. Do NOT end your loop."
    else
      if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then
        echo "  ⚠ STOP: brain.sh handover (every held #<nr> with state, SHA, next step), then bin/restart-self.sh stop — it opens the watchdog loop in a new zellij tab. Do NOT end your loop."
      else
        echo "  ⚠ STOP: brain.sh handover and one line via say.sh. Neither a watchdog loop nor zellij: ask the human for a restart. Do NOT end your loop — keep ticking."
      fi
    fi
  fi
fi

# The exit: only with --signal does "nothing to do" become a code of its own.
if [ "$WORK" = 0 ] && [ "$SIGNAL" = 1 ]; then
  echo "[$R] nothing for you — no model start needed."
  exit 4
fi
exit 0
