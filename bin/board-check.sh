#!/usr/bin/env bash
# Prueft, ob das GitHub Project und die Repo-Labels das Statusmodell aus kit.env abbilden.
#
#   bin/board-check.sh            nur pruefen, Exit 0 = alles abgebildet
#   bin/board-check.sh --write    bei Erfolg die IDs atomar nach board.env schreiben
#
# Geprueft wird:
#   1. das Project existiert und hat ein Einfachauswahl-Feld "Status"
#   2. jede Board-Option aus KIT_STATUS_MAP existiert mit genau diesem Namen
#   3. das Board hat keine Option, die der Loop nie setzt
#   4. die Reihenfolge der Optionen folgt der Vorwaertskante
#   5. im Repo existieren die Labels status:<schluessel> (ausser done), owner:<rolle>, Sprint-Label
#
# Ein fehlgeschlagener gh-Aufruf ist ein Fehlschlag, kein "Board leer".
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

WRITE=0; [ "${1:-}" = "--write" ] && WRITE=1

[ "$KIT_BOARD" = "github-project" ] || die "KIT_BOARD ist '$KIT_BOARD'. Der Board-Check gilt nur fuer KIT_BOARD=github-project."
case "$KIT_PROJECT_OWNER$KIT_PROJECT_NUMBER" in *UNKNOWN*) die "KIT_PROJECT_OWNER oder KIT_PROJECT_NUMBER steht auf UNKNOWN (kit.env)" ;; esac

# Quellen. Evals setzen die Fixture-Variablen und pruefen ohne Netz.
if [ -n "${KIT_BOARD_FIXTURE:-}" ]; then
  PROJECT_JSON="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["project"]))' "$KIT_BOARD_FIXTURE")"
  FIELDS_JSON="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["fields"]))' "$KIT_BOARD_FIXTURE")"
  LABELS_JSON="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["labels"]))' "$KIT_BOARD_FIXTURE")"
else
  "$BIN_DIR/preflight.sh" > /dev/null || die "Preflight fehlgeschlagen — stoppen und melden"
  PROJECT_JSON="$(gh project view "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --format json 2>&1)" \
    || die "Project $KIT_PROJECT_OWNER/$KIT_PROJECT_NUMBER nicht lesbar: $PROJECT_JSON"
  FIELDS_JSON="$(gh project field-list "$KIT_PROJECT_NUMBER" --owner "$KIT_PROJECT_OWNER" --format json 2>&1)" \
    || die "Felder nicht lesbar: $FIELDS_JSON"
  LABELS_JSON="$(gh label list --repo "$KIT_REPO" --limit 500 --json name 2>&1)" \
    || die "Labels von $KIT_REPO nicht lesbar: $LABELS_JSON"
fi

OWNING_ROLES="engineer-a engineer-b qa-ruthless simplicity-reviewer security-engineer acceptance-tester"

RESULT="$(python3 - "$KIT_STATUS_MAP" "$KIT_LABEL_PREFIX" "$KIT_OWNER_PREFIX" "$KIT_SPRINT_LABEL" "$OWNING_ROLES" \
  "$PROJECT_JSON" "$FIELDS_JSON" "$LABELS_JSON" <<'PY'
import json, sys
smap, lp, op, sprint, owning, pj, fj, lj = sys.argv[1:9]
want = [tuple(l.split("|", 1)) for l in smap.strip().splitlines() if "|" in l]
project = json.loads(pj); fields = json.loads(fj)
fields = fields["fields"] if isinstance(fields, dict) else fields   # gh: {"fields":[…]}, Fixture: […]
labels = {l["name"] for l in json.loads(lj)}

rows, fail = [], False
status = next((f for f in fields if f.get("name") == "Status"), None)
if not status or "options" not in status:
    print("FAIL|Feld 'Status'|Einfachauswahl-Feld 'Status' fehlt auf dem Board")
    sys.exit(0)
opts = [(o["name"], o["id"]) for o in status["options"]]
names = [n for n, _ in opts]

for key, name in want:
    if name in names:
        print(f"OK|Board-Option {name}|{key} → {dict(opts)[name]}")
    else:
        print(f"FAIL|Board-Option {name}|fehlt — Schluessel '{key}' kann nicht gesetzt werden")
for n in names:
    if n not in [w[1] for w in want]:
        print(f"FAIL|Board-Option {n}|ueberzaehlig — der Loop setzt diesen Status nie")
present = [n for n in names if n in [w[1] for w in want]]
expected = [w[1] for w in want if w[1] in names]
print(("OK" if present == expected else "FAIL") + f"|Reihenfolge|board: {' → '.join(present)}")
for key, _ in want:
    if key == "done":
        continue
    l = lp + key
    print(("OK" if l in labels else "FAIL") + f"|Label {l}|" + ("vorhanden" if l in labels else "fehlt im Repo"))
for r in owning.split():
    l = op + r
    print(("OK" if l in labels else "FAIL") + f"|Label {l}|" + ("vorhanden" if l in labels else "fehlt im Repo"))
print(("OK" if sprint in labels else "FAIL") + f"|Label {sprint}|" + ("vorhanden" if sprint in labels else "fehlt im Repo"))

env = [f'KIT_PROJECT_ID="{project["id"]}"', f'KIT_STATUS_FIELD_ID="{status["id"]}"']
for key, name in want:
    if name in names:
        env.append(f'KIT_OPTION_{key.upper().replace("-", "_")}="{dict(opts)[name]}"')
print("ENV|" + "\\n".join(env))
PY
)"

printf '%-5s %-34s %s\n' "" "Pruefpunkt" "Befund"
FAILS=0
while IFS='|' read -r verdict what detail; do
  [ "$verdict" = "ENV" ] && continue
  [ "$verdict" = "FAIL" ] && FAILS=$((FAILS + 1))
  printf '%-5s %-34s %s\n' "$verdict" "$what" "$detail"
done <<< "$RESULT"

echo
if [ "$FAILS" -gt 0 ]; then
  echo "board-check: $FAILS Pruefpunkt(e) FAIL — das Board bildet das Statusmodell nicht ab. board.env unveraendert."
  exit 1
fi
echo "board-check: alle Pruefpunkte OK — $KIT_PROJECT_OWNER/projects/$KIT_PROJECT_NUMBER bildet das Statusmodell ab."
if [ "$WRITE" = 1 ]; then
  {
    echo "# GENERIERT von bin/board-check.sh --write am $(now). Nicht von Hand editieren."
    echo "# Project: $KIT_PROJECT_OWNER/projects/$KIT_PROJECT_NUMBER"
    printf '%b\n' "$(printf '%s\n' "$RESULT" | grep '^ENV|' | cut -d'|' -f2-)"
  } | atomic_write "$BOARD_ENV"
  echo "board.env geschrieben: $(grep -c '^KIT_' "$BOARD_ENV") IDs"
fi
