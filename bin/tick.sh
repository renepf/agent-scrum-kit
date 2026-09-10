#!/usr/bin/env bash
# Eine Runde Lagebild. Jede Rolle ruft das in JEDER Loop-Runde als Erstes auf.
#
#   export KIT_ROLE=qa-ruthless
#   bin/tick.sh
#
# Idempotent. Fuenf Antworten in einem Aufruf:
#   1. registriert die Rolle, falls noetig — auch nach einem Reset mit neuer Session-ID
#   2. zeigt Chat-Eintraege, die diese Rolle noch nicht gesehen hat
#   3. zeigt, was davon DIREKT an sie gerichtet ist (@<rolle> in einer fremden Chatdatei)
#   4. zeigt ihre Warteschlange: nur die Zustaende, die sie laut KIT_QUEUES aufnimmt
#   5. zeigt ihren Kontextstand und ein etwaiges STOP
#
# Ohne aktiven Sprint meldet es das und endet mit Exit 0. Warten ist kein Fehler.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BIN="$(dirname "${BASH_SOURCE[0]}")"
R="$(role)"

if [ ! -s "$CURRENT_FILE" ]; then
  echo "[$R] kein aktiver Sprint. Der product-owner schneidet ihn mit bin/sprint-new.sh. Nichts zu tun."
  exit 0
fi

SPRINT="$(sprint_dir)"
SID="$(session_id)"

# --- 1. Registrierung ---------------------------------------------------------
if ! grep -q "| $R | $SID |" "$SPRINT/roster.md" 2>/dev/null; then
  "$BIN/register.sh" "$SID" > /dev/null
  echo "[$R] registriert · session $SID"
fi

# --- 2 + 3. Ungesehene Eintraege und Direktansprache ---------------------------
# Gemerkt werden die gesehenen datei:zeile-Verweise, nicht eine Zeilenzahl. Eine Zahl
# versagt, sobald zwei Eintraege dieselbe Minute tragen: der Index sortiert dann nach
# Dateiname, und ein neuer Eintrag kann vor einem alten landen.
[ -f "$SPRINT/INDEX.md" ] || "$BIN/reindex.sh" > /dev/null || die "reindex.sh fehlgeschlagen — Tick abgebrochen, nicht still weiter"
SEEN="$SPRINT/.tick-$R"

with_lock "$SEEN.lock" python3 - "$SPRINT" "$R" "$SEEN" <<'PY'
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
    print(f"\n── neu im Chat seit deinem letzten Tick ({len(new)}) ──")
    for _, row in new:
        print(row)

# Direktansprache: nur in NEUEN Eintraegen fremder Rollen. Einmal gezeigt, nie wieder —
# sonst liest jede Runde dieselben Zeilen neu.
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
    print("\n── direkt an dich gerichtet ──")
    for ref, head in hits:
        print(f"  {ref}  {head}")

tmp = seen_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("\n".join(sorted(seen | {ref for ref, _ in rows})) + "\n")
os.replace(tmp, seen_path)
PY

# --- 4. Warteschlange ------------------------------------------------------------
Q="$(queue_of "$R")"
if [ -z "$Q" ]; then
  echo
  echo "[$R] nimmt keine Tickets auf."
else
  "$BIN/preflight.sh" > /dev/null || { echo "[$R] Preflight FEHLGESCHLAGEN — stoppen und melden, nicht raten." >&2; exit 1; }
  [ "$Q" = "*" ] && Q="$(echo "$KIT_STATES" | sed 's/ *done *//')"
  SPRINT_TICKETS=" $("$BIN/tickets.sh" list "${KIT_SPRINT_LABEL:-sprint:current}" | tr '\n' ' ') "
  echo
  echo "── deine Warteschlange ($Q) ──"
  found=0
  for st in $Q; do
    for nr in $("$BIN/tickets.sh" list "$KIT_LABEL_PREFIX$st"); do
      case "$SPRINT_TICKETS" in *" $nr "*) ;; *) continue ;; esac
      who="$("$BIN/tickets.sh" assignees "$nr" | tr '\n' ',' | sed 's/,$//')"
      printf '  #%-5s [%-11s] %-14s %s\n' "$nr" "$st" "${who:-frei}" "$("$BIN/tickets.sh" title "$nr" | cut -c1-58)"
      found=1
    done
  done
  [ "$found" = 1 ] || echo "  (nichts in $Q — warte)"
fi

# --- 5. Kontextstand ---------------------------------------------------------------
if [ -f "$SPRINT/budget.md" ]; then
  MINE="$(grep "^| $R |" "$SPRINT/budget.md" || true)"
  [ -n "$MINE" ] && { echo; echo "── dein Budget ──"; echo "$MINE"; }
  if grep -q "^STOP $R\$" "$SPRINT/budget.md"; then
    echo "  STOP: an der naechsten Ticketgrenze Uebergabe schreiben, dann neue Session."
  fi
fi
exit 0
