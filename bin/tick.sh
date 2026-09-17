#!/usr/bin/env bash
# Eine Runde Lagebild. JEDE Rolle ruft das zu Beginn JEDER Loop-Runde auf.
#
#   export KIT_ROLE=qa-ruthless
#   bin/tick.sh
#
# Idempotent. In dieser Reihenfolge:
#   1. registrieren und Zwillingssperre erneuern — neue Session-ID holt das Gedaechtnis zurueck
#   2. Rueckweisungen zuerst (nur Engineers): sie haben Vorrang vor jedem neuen Ticket
#   3. eigene Tickets, dann freie Tickets aus der eigenen Warteschlange
#   4. ungesehene Chat-Eintraege und Erwaehnungen @<rolle> — je genau einmal
#   5. Tokenstand, STOP-Flag
# Ohne aktiven Sprint endet es mit Exit 0 — eine wartende Rolle ist kein Fehler.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

R="$(role)"
if [ ! -s "$CURRENT_FILE" ]; then
  echo "[$R] kein aktiver Sprint. Der product-owner schneidet ihn mit bin/sprint-new.sh. Nichts zu tun."
  exit 0
fi

SPRINT="$(sprint_dir)"
SID="$(session_id)"
STATE="$SPRINT/.tick-$R"
P="$KIT_LABEL_PREFIX"; O="$KIT_OWNER_PREFIX"

# Hintergrund-Session: hat KIT_ROLE geerbt, ist aber keine Rolle — kein Anker, kein Tick.
BG="$KIT_ROOT/adapters/$KIT_HOST/is-background.sh"
if [ -x "$BG" ] && "$BG"; then
  echo "[$R] Hintergrund-Session — keine Rolle, kein Tick. Nichts tun."
  exit 3
fi

# Anker toter oder neu vergebener PIDs wegraeumen. Sonst haelt die Zwillingssperre einen fremden
# Prozess fuer eine laufende Rolle.
for f in "$PID_ROLES"/*; do
  [ -f "$f" ] || continue
  host_alive "$(basename "$f")" || rm -f "$f"
done

# Rollen-Anker bei JEDEM Tick — nicht erst bei Neuregistrierung. Sonst fehlt er genau dann,
# wenn er gebraucht wird: nach dem ersten Kontext-Reset.
anchor_role "$R"

# --- 1. Registrierung + Zwillingssperre --------------------------------------
NEW_SESSION=0
grep -q "| $R | $SID |" "$SPRINT/roster.md" 2>/dev/null || NEW_SESSION=1
"$BIN_DIR/register.sh" "$SID" > /dev/null   # bricht ab, wenn ein Zwilling laeuft
if [ "$NEW_SESSION" = 1 ]; then
  echo "[$R] neue Session $SID — Gedaechtnis zurueckholen (bin/brain.sh recall):"
  "$BIN_DIR/brain.sh" recall
fi

# --- 2./3. Tickets -----------------------------------------------------------
QUEUE="$(printf '%s\n' "$KIT_QUEUE_MAP" | grep "^$R|" | cut -d'|' -f2 || true)"
if [ -z "$QUEUE" ]; then
  echo "[$R] nimmt keine Tickets auf."
else
  "$BIN_DIR/preflight.sh" > /dev/null 2>&1 || { echo "[$R] Preflight FEHLGESCHLAGEN — stoppen und melden, nicht raten." >&2; exit 1; }
  SPRINT_JSON="$("$BIN_DIR/tickets.sh" sprint)" || { echo "[$R] Ticketliste nicht lesbar — Fehlschlag, kein leerer Sprint." >&2; exit 1; }

  # Rueckweisung: owner:<engineer> in in-progress, letzter Statuswechsel NICHT vom Engineer selbst.
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
        "$BIN_DIR/tickets.sh" comments "$n" | python3 -c '
import json, re, sys
me, n, ip = sys.argv[1], sys.argv[2], sys.argv[3]
heads = [(m.group(1), m.group(2), b) for b in json.load(sys.stdin)
         for m in [re.match(r"^\*\*([^*]+)\*\* — ([a-z-]+) ", b)] if m]
if heads and heads[-1][0] == ip and heads[-1][1] != me:
    note = heads[-1][2].split("\n", 2)[-1].strip()
    print(f"↩ #{n} ZURUECKGEWIESEN von {heads[-1][1]} — hat Vorrang vor jedem neuen Ticket:")
    print(f"    {note[:160]}")
    print(f"    Befund lesen, fixen, pushen, dann status.sh {n} rfr. Alte PASS-Verdicts gelten fuer den neuen HEAD nicht.")
' "$R" "$n" "$IP"
      done
      ;;
  esac

  echo "── deine Warteschlange ($QUEUE) ──"
  printf '%s' "$SPRINT_JSON" | QUEUE="$QUEUE" python3 -c '
import json, os, sys
p, o, role = sys.argv[1], sys.argv[2], sys.argv[3]
want = os.environ["QUEUE"].split(",")
mine, free = [], []
for i in json.load(sys.stdin):
    names = [l["name"] for l in i["labels"]]
    st = next((l[len(p):] for l in names if l.startswith(p)), "backlog")
    owners = ",".join(l[len(o):] for l in names if l.startswith(o)) or "frei"
    line = "  #%-5s [%-11s] %-22s %s" % (i["number"], st, owners, i["title"][:50])
    if o + role in names:
        mine.append(line)
    elif "*" in want or st in want:
        free.append(line)
print("  deine:"); print("\n".join(mine) if mine else "    (keins)")
print("  frei fuer dich (" + ",".join(want) + "):"); print("\n".join(free) if free else "    (nichts — Runde beenden)")
' "$P" "$O" "$R"
fi

# --- 3b. Backlog ohne Artefaktkette -------------------------------------------
# Wer backlog aufnimmt (requirements-engineer) oder alles sieht (product-owner), sieht hier, welchem
# Ticket noch ein Glied fehlt. planned und sprint-new.sh lehnen genau diese Tickets ab.
case ",$QUEUE," in
  *,backlog,*|*"*"*)
    LUECKEN=""
    for b in $("$BIN_DIR/tickets.sh" list "${P}backlog" 2>/dev/null); do
      fehlt=""
      for a in intent.md spec.md plan.md; do
        grep -q '[^[:space:]]' "$TICKETS_DIR/$b/$a" 2>/dev/null || fehlt="$fehlt $a"
      done
      [ -n "$fehlt" ] && LUECKEN="$LUECKEN  #$b fehlt:$fehlt
"
    done
    if [ -n "$LUECKEN" ]; then
      echo "── backlog ohne Artefaktkette (so lehnen sprint-new.sh und planned ab) ──"
      printf '%s' "$LUECKEN"
    fi
    ;;
esac

# --- 3c. Kanban: nur der product-owner plant, nur er sieht die Zahlen ----------
if [ "$R" = "product-owner" ] && [ -n "${SPRINT_JSON:-}" ]; then
  printf '%s' "$SPRINT_JSON" | MIN="${KIT_MIN_PLANNED:-7}" STOP="${KIT_QUEUE_STOP:-2}" \
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
print("── Kanban ──")
print("  geplant %d (Ziel mindestens %d) · in Arbeit %d (Engineers %d) · Pruefschlange %d · Testschlange %d"
      % (planned, mn, wip, eng, review, test))
if review > stop or test > stop:
    print("  Planungsstopp: Pruef- oder Testschlange ueber %d. Nichts Neues planen, bis sie auf %d faellt." % (stop, stop))
elif planned < mn:
    print("  zu wenig geplant: %d statt %d — nachschneiden, sonst laeuft das Team leer." % (planned, mn))
if wip < eng:
    print("  %d Engineer(s) ohne Ticket: freies planned-Ticket aufnehmen, sonst ein nicht blockiertes." % (eng - wip))
' "$P"
fi

# --- 4. Chat: ungesehene Eintraege und Direktansprache, je genau einmal ----------
# Gemerkt werden die gesehenen datei:zeile-Verweise, nicht eine Zeilenzahl. Eine Zahl
# versagt, sobald zwei Eintraege dieselbe Minute tragen: der Index sortiert dann nach
# Dateiname, und ein neuer Eintrag kann vor einem alten landen.
[ -f "$SPRINT/INDEX.md" ] || "$BIN_DIR/reindex.sh" > /dev/null || die "reindex.sh fehlgeschlagen — Tick abgebrochen, nicht still weiter"
SEEN="$SPRINT/.tick-$R"
with_lock "$SEEN.lock" python3 - "$SPRINT" "$R" "$SEEN" <<'PY2'
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
    print(f"[{role}] keine neuen Chat-Eintraege.")
else:
    print(f"── neu im Chat seit deinem letzten Tick ({len(new)}) ──")
    for _, row in new:
        print(row)
# Direktansprache: nur in NEUEN Eintraegen fremder Rollen. Einmal gezeigt, nie wieder.
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
    print("── direkt an dich gerichtet ──")
    for ref, head in hits:
        print(f"  {ref}  {head}")
tmp = seen_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("\n".join(sorted(seen | {ref for ref, _ in rows})) + "\n")
os.replace(tmp, seen_path)
PY2

# --- 5. Budget ---------------------------------------------------------------
if [ -f "$SPRINT/budget.md" ]; then
  MINE="$(grep "^| $R |" "$SPRINT/budget.md" || true)"
  [ -z "$MINE" ] || { echo "── dein Budget ──"; echo "$MINE"; }
  case "$MINE" in *Warnung*) echo "  Warnung: kein neues Ticket annehmen. Deinen Loop NICHT beenden — weiter ticken." ;; esac
  if grep -q "^STOP $R\$" "$SPRINT/budget.md"; then
    if [ "${KIT_ROLE_LOOP:-}" = "1" ]; then
      echo "  ⚠ STOP: brain.sh handover (jedes gehaltene #<nr> mit Stand, SHA, naechstem Schritt), dann bin/restart-self.sh stop — die Waechter-Schleife startet dich frisch. Deinen Loop NICHT beenden."
    else
      if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then
        echo "  ⚠ STOP: brain.sh handover (jedes gehaltene #<nr> mit Stand, SHA, naechstem Schritt), dann bin/restart-self.sh stop — es oeffnet die Waechter-Schleife in einem neuen zellij-Tab. Deinen Loop NICHT beenden."
      else
        echo "  ⚠ STOP: brain.sh handover und eine Zeile per say.sh. Weder Waechter-Schleife noch zellij: den Menschen um einen Neustart bitten. Deinen Loop NICHT beenden — weiter ticken."
      fi
    fi
  fi
fi
exit 0
