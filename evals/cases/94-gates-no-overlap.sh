#!/usr/bin/env bash
CASE_DESC="kein Ueberlappen: planned, revise.sh und sprint-new.sh lehnen OWNS ab, die sich mit einem freigegebenen Ticket desselben Sprints ueberschneiden"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
st() { KIT_ROLE="$1" "$BIN/status.sh" "$2" "$3" x 2>&1; }
im_sprint() { sandbox_issue "$1" '{"labels":["sprint:current"]}'; }
kommentare() { KIT_ROLE=product-owner "$BIN/tickets.sh" comments "$1" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }

# a) Glob-Paare: getrennt nur, wenn ein woertliches Segment abweicht oder eine einzelne Datei nicht getroffen wird
while IFS='|' read -r a b soll; do
  [ -n "$a" ] || continue
  n=$((n + 1))
  printf '#a\t%s\n#b\t%s\n' "$a" "$b" | python3 "$BIN/gates.py" overlap > /dev/null 2>&1 && ist=getrennt || ist=ueberlappt
  [ "$ist" = "$soll" ] || fail "a:'$a'~'$b'=$ist"
done <<'TABELLE'
src/api/**|src/api/util.kt|ueberlappt
src/api/**|src/web/**|getrennt
src/api/**|src/**|ueberlappt
src/*.py|src/*.kt|ueberlappt
README.md|README.md|ueberlappt
README.md|docs/README.md|getrennt
docs/|docs/a.md|ueberlappt
src/a.py|src/b.py|getrennt
src|src/a.py|getrennt
**/test_*.py|src/api/test_x.py|ueberlappt
**/test_*.py|src/api/x.py|getrennt
TABELLE

# b) planned: #71 haelt src/api/**, #72 will src/api/util.kt → abgelehnt, #71 genannt, nichts geschrieben
sandbox_plannable 71 "src/api/**"; im_sprint 71
st product-owner 71 planned > /dev/null || fail b:71-planned
sandbox_plannable 72 "src/api/util.kt"; im_sprint 72
s1="$(sandbox_snap 72)"; ob="$(st product-owner 72 planned)"; s2="$(sandbox_snap 72)"
expect b-ueberlappt "$ob" '*abgelehnt*#72 und #71*src/api/util.kt ~ src/api/*'
n=$((n + 1)); [ "$s1" = "$s2" ] || fail b:Zustand-veraendert

# c) ein freigegebenes Ticket ausserhalb des Sprints zaehlt nicht
sandbox_issue 74 '{"comments":["**Planned** — product-owner · eval · session `e`\n\nOWNS Revision 1: `src/web/**`"]}'
sandbox_plannable 73 "src/web/**"; im_sprint 73
expect c-anderer-Sprint "$(st product-owner 73 planned)" '*backlog → planned*'

# d) ein Sprint-Ticket ohne Freigabe (noch backlog) zaehlt nicht
sandbox_plannable 75 "src/api2/**"; im_sprint 75
sandbox_plannable 72 "src/api2/**"
expect d-ohne-Freigabe "$(st product-owner 72 planned)" '*backlog → planned*'

# e) revise.sh: #73 will src/api/client.kt dazu → ueberlappt mit #71, kein Kommentar; getrennt geht durch
k0="$(kommentare 73)"
sandbox_plannable 73 "src/web/**, src/api/client.kt"
expect e-revise-ueberlappt "$(KIT_ROLE=product-owner "$BIN/revise.sh" 73 "src/web/**, src/api/client.kt" "Client gehoert dazu" 2>&1)" '*abgelehnt*#73 und #71*src/api/client.kt*'
n=$((n + 1)); [ "$(kommentare 73)" = "$k0" ] || fail "e:Kommentar-trotz-Ablehnung"
sandbox_plannable 73 "src/web/**, assets/**"
expect e-revise-getrennt "$(KIT_ROLE=product-owner "$BIN/revise.sh" 73 "src/web/**, assets/**" "Assets gehoeren dazu" 2>&1)" '*Revision 1 → 2*'

# f) sprint-new.sh: #81 lib/**, #82 lib/x.py → abgelehnt, kein Sprint angelegt; getrennt geht durch
sandbox_plannable 81 "lib/**"; sandbox_plannable 82 "lib/x.py"
dirs0="$(ls "$SANDBOX/sprints" | tr '\n' ' ')"; cur0="$(cat "$SANDBOX/sprints/CURRENT")"
expect f-sprint-ueberlappt "$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" zwei 81 82 2>&1)" '*abgelehnt*#81 und #82*lib/x.py*'
n=$((n + 1)); [ "$(ls "$SANDBOX/sprints" | tr '\n' ' ')" = "$dirs0" ] && [ "$(cat "$SANDBOX/sprints/CURRENT")" = "$cur0" ] || fail f:Sprint-trotzdem-angelegt
sandbox_plannable 82 "tools/**"
expect f-sprint-getrennt "$(KIT_ROLE=product-owner "$BIN/sprint-new.sh" zwei 81 82 2>&1)" '*S-002-zwei angelegt*'

# g) gh-Pfad: Ueberschneidung mit #91; sind die Kommentare von #91 nicht lesbar, ist das ein Fehlschlag
fake_gh "$(python3 - <<'PY'
import json
freigabe = "**Planned** — product-owner · eval · session `e`\n\nOWNS Revision 1: `pkg/core/**`"
db = {
    "91": {"labels": ["sprint:current", "status:planned"], "assignees": [], "state": "OPEN", "comments": [freigabe], "board": "o-planned"},
    "92": {"labels": ["sprint:current"], "assignees": [], "state": "OPEN", "comments": [], "board": None, "body": "AC-1: das Ergebnis ist beobachtbar"},
}
print(json.dumps(db))
PY
)"
sandbox_ledger 92 <<'LEDGER'
# Gates: #92

OWNS: pkg/core/io.go

- [ ] AC-1: das Ergebnis ist beobachtbar
  CHECK: python3 tools/check_result.py
  EXPECT: ergebnis geprueft
  EVIDENCE: pending
LEDGER
expect g-gh-ueberlappt "$(st product-owner 92 planned)" '*abgelehnt*#92 und #91*pkg/core/io.go*'
expect g-gh-Kommentare-Fehler "$(FAKE_GH_FAIL=comments st product-owner 92 planned)" '*#91: Kommentare nicht lesbar*'

observe "$((n - falsch))/$n Pruefungen bestanden · 11 Glob-Paare · planned mit Byte-Vergleich, anderer Sprint, ohne Freigabe · revise ueberlappt/getrennt · sprint-new ueberlappt ohne Anlegen/getrennt · gh: Ueberschneidung, Kommentare-Fehler${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
