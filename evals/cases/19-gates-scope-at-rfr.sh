#!/usr/bin/env bash
CASE_DESC="rfr nur, wenn jede Datei des PR, bei Umbenennung auch der alte Pfad, in der OWNS-Revision liegt, die der product-owner am Issue freigegeben hat; Revision, Globs, gh-Pfad"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 120)'" ;; esac; }
st() { KIT_ROLE="$1" "$BIN/status.sh" "$2" "$3" x 2>&1; }
rv() { KIT_ROLE="$1" "$BIN/revise.sh" 41 "$2" "$3" 2>&1; }
revision() { KIT_ROLE=product-owner "$BIN/tickets.sh" comments 41 | python3 "$BIN/gates.py" approved 2>/dev/null | cut -f1; }
kommentare() { KIT_ROLE=product-owner "$BIN/tickets.sh" comments 41 | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
unveraendert() { # name nr befehl...
  local name="$1" nr="$2" s1 s2; shift 2
  s1="$(sandbox_snap "$nr")"; "$@" > /dev/null 2>&1; s2="$(sandbox_snap "$nr")"
  n=$((n + 1)); [ "$s1" = "$s2" ] || fail "$name:Zustand-veraendert"
}

# a) Ledger ohne OWNS: planned abgelehnt
sandbox_issue 42 '{"body":"AC-1: das Ergebnis ist messbar"}'
printf '# Gates: #42\n\n- [ ] AC-1: das Ergebnis ist messbar\n  CHECK: python3 tools/check.py\n  EXPECT: gemessen\n  EVIDENCE: pending\n' | sandbox_ledger 42
expect a-ohne-OWNS "$(st product-owner 42 planned)" '*ohne OWNS*'

# b) planned haelt OWNS als Revision 1 im eigenen Issue-Kommentar fest
sandbox_issue 41 '{"pr":{"number":410,"head":"41414141aa","comments":[],"files":["src/export/writer.py","tests/export/test_writer.py","README.md"]}}'
sandbox_plannable 41 "src/export/**, tests/export/**"
st product-owner 41 planned > /dev/null || fail b:planned
n=$((n + 1)); [ "$(revision)" = 1 ] || fail "b:revision='$(revision)'"
st engineer-a 41 in-progress > /dev/null || fail b:in-progress

# c) README.md ausserhalb: nichts geschrieben (schon beim ersten Versuch), abgelehnt, genau diese Datei genannt
unveraendert c-schreibt-nichts 41 st engineer-a 41 rfr
oc="$(st engineer-a 41 rfr)"
expect c-ausserhalb "$oc" '*ausserhalb*README.md*'
case "$oc" in *writer.py*) fail c:Datei-in-OWNS-genannt ;; esac

# d) Engineer erweitert OWNS im Ledger selbst: zaehlt nicht
sandbox_plannable 41 "src/export/**, tests/export/**, README.md"
expect d-Selbst-Erweiterung "$(st engineer-a 41 rfr)" '*README.md*revise.sh*'

# d2) Engineer schreibt eine Freigabe-Zeile in einen eigenen Kommentar: zaehlt nicht
KIT_ROLE=engineer-a "$BIN/tickets.sh" comment 41 "**Notiz** — engineer-a · jetzt · session \`x\`

OWNS Revision 9: \`src/**, tests/**, README.md\`"
expect d2-fremde-Freigabezeile "$(st engineer-a 41 rfr)" '*Revision 1*ausserhalb*README.md*'

# e) Revision abgelehnt: falsche Rolle, Aufruf ungleich Ledger, ganze Wurzel, ** im Segment,
#    nur umsortiert, absoluter Pfad. Keine Ablehnung schreibt einen Kommentar.
k0="$(kommentare)"
expect e1-Rolle "$(rv engineer-a "src/export/**, tests/export/**, README.md" "brauche README")" '*nur der product-owner*'
expect e2-ungleich-Ledger "$(rv product-owner "src/**" "anders als das Ledger")" '*das Ledger nennt*'
# Die Ledger-Pruefung selbst muss ablehnen ("abgelehnt — Zeile ..."), nicht erst der Vergleich mit dem Aufruf,
# der ihre Fehlermeldung als "das Ledger nennt '...'" zitieren wuerde.
sandbox_plannable 41 "**"
expect e3-Wurzel "$(rv product-owner "**" "alles")" '*abgelehnt — Zeile*ganze Wurzel*'
sandbox_plannable 41 "src**"
expect e4-Segment "$(rv product-owner "src**" "Segment")" '*abgelehnt — Zeile*ganzes Pfadsegment*'
sandbox_plannable 41 "tests/export/**, src/export/**"
expect e5-unveraendert "$(rv product-owner "tests/export/**,src/export/**" "nur umsortiert")" '*keine neue Revision*'
sandbox_plannable 41 "/etc/**"
expect e6-absolut "$(rv product-owner "/etc/**" "absolut")" '*abgelehnt — Zeile*relativ*'
sandbox_plannable 41 "src/export/**, tests/export/**, README.md"
sandbox_issue 41 '{"body":"AC-1: Export schreibt eine Datei\nAC-2: README nennt den Export"}'
expect e7-AC-ohne-Gate "$(rv product-owner "src/export/**, tests/export/**, README.md" "AC-2 fehlt im Ledger")" '*abgelehnt — AC ohne Gate*AC-2*'
n=$((n + 1)); [ "$(kommentare)" = "$k0" ] || fail "e:Kommentar-trotz-Ablehnung(${k0}->$(kommentare))"
n=$((n + 1)); [ "$(revision)" = 1 ] || fail "e:revision='$(revision)'"

# f) product-owner gibt README frei: Revision 2 nennt alten Umfang, neuen Umfang und Grund
sandbox_plannable 41 "src/export/**, tests/export/**, README.md"
rv product-owner "README.md, src/export/**, tests/export/**" "AC-1 verlangt den Hinweis im README" > /dev/null || fail f:revise
n=$((n + 1)); [ "$(revision)" = 2 ] || fail "f:revision='$(revision)'"
kf="$(KIT_ROLE=product-owner "$BIN/tickets.sh" comments 41 | python3 -c 'import json,sys; print(" ".join(c for c in json.load(sys.stdin) if c.startswith("**OWNS Revision 2**")))')"
expect f-Kommentar "$kf" '*Revision 1*src/export/*OWNS Revision 2:*README.md*AC-1 verlangt den Hinweis*'

# g) Gegenprobe: jetzt geht rfr durch
expect g-rfr "$(st engineer-a 41 rfr)" '*in-progress → rfr*'

# h) ohne verknuepften PR keine Abgabe
sandbox_plannable 43
st product-owner 43 planned > /dev/null; st engineer-b 43 in-progress > /dev/null
expect h-ohne-PR "$(st engineer-b 43 rfr)" '*kein verknuepfter PR*'

# i) Globs: je Form ein Treffer und ein Nicht-Treffer; eine leere Dateiliste ist ein Fehlschlag
while IFS='|' read -r g f soll; do
  [ -n "$g" ] || continue
  n=$((n + 1))
  printf '%s\n' "$f" | python3 "$BIN/gates.py" scope "$g" > /dev/null 2>&1 && ist=drin || ist=draussen
  [ "$ist" = "$soll" ] || fail "i:'$g'~'$f'=$ist"
done <<'TABELLE'
src/**|src/a.py|drin
src/**|src/x/y.py|drin
src/**|srcevil/a.py|draussen
src/*.py|src/a.py|drin
src/*.py|src/x/a.py|draussen
**/test_*.py|test_a.py|drin
**/test_*.py|a/b/test_a.py|drin
**/test_*.py|a/b/a.py|draussen
docs/|docs/a/b.md|drin
docs/|docsx/a.md|draussen
README.md|README.md|drin
README.md|x/README.md|draussen
a?.md|ab.md|drin
a?.md|a/.md|draussen
TABELLE
expect i-leere-Liste "$(printf '' | python3 "$BIN/gates.py" scope "src/**" 2>&1)" '*leer*'

# j) unzulaessiges OWNS lehnt planned ab
for bad in "**" "./**" "*" "**/*" "src**" "/etc/**" "../x/**"; do
  n=$((n + 1))
  printf '# Gates\n\nOWNS: %s\n\n- [ ] AC-1: x\n  CHECK: python3 tools/check_x.py\n  EXPECT: x gemessen\n  EVIDENCE: pending\n' "$bad" > "$SANDBOX/bad.md"
  printf 'AC-1: x\n' | python3 "$BIN/gates.py" planned "$SANDBOX/bad.md" > /dev/null 2>&1 && fail "j:'$bad'-durch"
done

# k) gh-Pfad (vorgetaeuschtes gh): Umbenennung, zwei PRs, Fehler der Dateiliste, Gegenprobe
fake_gh "$(python3 - <<'PY'
import json
freigabe = "**Planned** — product-owner · eval · session `e`\n\neval\n\nOWNS Revision 1: `src/**`"
def ticket(prs):
    return {"labels": ["status:in-progress", "owner:engineer-a"], "assignees": [], "state": "OPEN",
            "comments": [freigabe], "board": "o-inprogress", "prs": prs}
db = {"60": ticket(["600"]), "61": ticket(["610", "611"]), "62": ticket(["620"]), "63": ticket(["630"])}
db["pulls"] = {
    "600": {"head": "60606060aa", "files": [{"filename": "src/billing.py", "previous_filename": "legacy/billing.py"}]},
    "610": {"head": "61616161aa", "files": [{"filename": "src/a.py"}]},
    "611": {"head": "61616161bb", "files": [{"filename": "infra/deploy.yml"}]},
    "620": {"head": "62626262aa", "files": [{"filename": "src/a.py"}]},
    "630": {"head": "63636363aa", "files": [{"filename": "src/b.py", "previous_filename": "src/a.py"}]},
}
print(json.dumps(db))
PY
)"
expect k-Umbenennung "$(st engineer-a 60 rfr)" '*ausserhalb*legacy/billing.py*'
expect k-zwei-PRs "$(st engineer-a 61 rfr)" '*mehrere verknuepfte PRs*'
expect k-Dateiliste-Fehler "$(FAKE_GH_FAIL=pr-files st engineer-a 62 rfr)" '*Dateiliste nicht lesbar*'
expect k-Gegenprobe "$(st engineer-a 63 rfr)" '*in-progress → rfr*'

observe "$((n - falsch))/$n Pruefungen bestanden · Datei-Backend: OWNS-Pflicht, Revision 1 am Issue, ausserhalb, Selbst-Erweiterung, fremde Freigabezeile, 7 abgelehnte Revisionen, Revision 2, rfr, ohne PR · 14 Globs + leere Liste · 7 unzulaessige OWNS · gh: Umbenennung, zwei PRs, Dateiliste-Fehler, Gegenprobe${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
