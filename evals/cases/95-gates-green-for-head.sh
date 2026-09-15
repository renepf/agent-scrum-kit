#!/usr/bin/env bash
CASE_DESC="rft nur, wenn jedes ausfuehrbare Gate fuer den aktuellen HEAD gruen gelaufen ist; Merge nur, wenn zusaetzlich jedes manuelle Gate einen Beleg fuer diesen HEAD traegt"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
check() { n=$((n + 1)); "${@:2}" || fail "$1"; }

# Ein Projekt mit einem Commit. Der PR von #51 zeigt auf dessen HEAD.
P="$SANDBOX/projekt"
mkdir -p "$P/tools"
cat > "$P/tools/check_export.py" <<'PY'
import pathlib, sys
if pathlib.Path("export.txt").read_text().strip() != "3 zeilen":
    print("export falsch")
    sys.exit(1)
print("export geprueft: 3 zeilen")
PY
echo "3 zeilen" > "$P/export.txt"
git -C "$P" init -q && git -C "$P" add -A && git -C "$P" commit -qm eins || { echo "BEOBACHTET: git-Commit im Sandkasten gescheitert (Identitaet aus ~/.gitconfig?)"; exit 1; }
head1="$(git -C "$P" rev-parse HEAD)"; h1="${head1:0:8}"

pr() { # <head> <labels-json>
  sandbox_issue 51 "{\"labels\":$2,\"pr\":{\"number\":510,\"head\":\"$1\",\"comments\":[],\"checks\":\"pass\",\"state\":\"OPEN\",\"files\":[\"export.txt\"]}}"
  for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS" "MERGE-GATE OK"; do sandbox_pr_comment 51 "$v — HEAD \`${1:0:8}\`, eval"; done
}
ledger() { # <check> <expect>
  sandbox_ledger 51 <<LEDGER
# Gates: #51 Export

OWNS: export.txt, tools/**

- [ ] AC-1: Export hat 3 Zeilen
  CHECK: $1
  EXPECT: $2
  EVIDENCE: pending

- [ ] AC-2: Hinweis am laufenden Bau sichtbar
  EVIDENCE: pending
LEDGER
}
GUT_CHECK="python3 tools/check_export.py"; GUT_EXPECT="export geprueft: 3 zeilen"
IN_REVIEW='["status:in-review","owner:qa-ruthless"]'
sandbox_issue 51 '{"body":"AC-1: Export hat 3 Zeilen\nAC-2: Hinweis am laufenden Bau sichtbar"}'
pr "$head1" "$IN_REVIEW"
ledger "$GUT_CHECK" "$GUT_EXPECT"
rft() { KIT_ROLE=qa-ruthless "$BIN/status.sh" 51 rft x 2>&1; }
run() { (cd "$P" && KIT_ROLE=engineer-a "$BIN/gates.sh" run 51 2>&1); }
L="$SANDBOX/tickets/51/GATES.md"

# a) drei PASS, aber AC-1 nie gelaufen: rft abgelehnt
expect a-nie-gelaufen "$(rft)" '*abgelehnt*AC-1*'

# b) Lauf auf dem HEAD des PR: AC-1 abgehakt, Beleg nennt HEAD; rft geht durch
expect b-lauf "$(run)" '*AC-1*gruen*'
check b-abgehakt grep -q '^- \[x\] AC-1:' "$L"
check b-beleg-head grep -q "EVIDENCE: v1 head=$h1 " "$L"
check b-manuell-unberuehrt grep -q '^- \[ \] AC-2:' "$L"
expect b-rft "$(rft)" '*in-review → rft*'

# c) neuer Push: der Beleg gilt dem alten HEAD, rft abgelehnt
echo "notiz" > "$P/NOTIZ.md"; git -C "$P" add -A && git -C "$P" commit -qm zwei
head2="$(git -C "$P" rev-parse HEAD)"; h2="${head2:0:8}"
pr "$head2" "$IN_REVIEW"
expect c-alter-HEAD "$(rft)" '*abgelehnt*AC-1*'

# d) Arbeitsbaum steht nicht auf dem HEAD des PR: kein Lauf, kein Beleg
git -C "$P" checkout -q "$head1"
vorher="$(cat "$L")"
expect d-falscher-checkout "$(run)" "*$h1*$h2*"
check d-ledger-unveraendert [ "$(cat "$L")" = "$vorher" ]
git -C "$P" checkout -q -

# e) Lauf auf dem neuen HEAD: rft geht durch
expect e-lauf "$(run)" '*AC-1*gruen*'
expect e-rft "$(rft)" '*in-review → rft*'

# f) Gate-Definition nach dem Lauf geaendert: der Beleg passt nicht mehr
pr "$head2" "$IN_REVIEW"
python3 - "$L" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("CHECK: python3 tools/check_export.py", "CHECK: python3 tools/check_export.py --neu"))
PY
expect f-definition-geaendert "$(rft)" '*abgelehnt*AC-1*'

# g) Fehlschlaege: Exit 0 ohne EXPECT, EXPECT mit Exit 1, Zeitueberschreitung. Jeder hakt ab und setzt pending.
#    Die Zeitgrenze kommt aus kit.env — eine Umgebungsvariable vor dem Aufruf ueberschreibt sie nicht.
echo 'KIT_GATE_TIMEOUT="2"' >> "$KIT_ENV_FILE"
for fall in "exit0-ohne-expect|$GUT_CHECK|export geprueft: 4 zeilen" \
            "expect-mit-exit1|python3 -c \"print('$GUT_EXPECT'); import sys; sys.exit(1)\"|$GUT_EXPECT" \
            "zeitueberschreitung|python3 -c \"import time; time.sleep(5); print('$GUT_EXPECT')\"|$GUT_EXPECT"; do
  name="${fall%%|*}"; rest="${fall#*|}"; chk="${rest%%|*}"; exp="${rest#*|}"
  ledger "$chk" "$exp"
  # Vorher abgehakt mit altem Beleg: ein gescheiterter Lauf muss beides zuruecknehmen.
  python3 - "$L" "$h2" <<'PY'
import sys
p, h = sys.argv[1:3]; t = open(p).read()
t = t.replace("- [ ] AC-1:", "- [x] AC-1:", 1).replace("EVIDENCE: pending", "EVIDENCE: v1 head=%s alt" % h, 1)
open(p, "w").write(t)
PY
  og="$(cd "$P" && KIT_ROLE=engineer-a "$BIN/gates.sh" run 51 2>&1)"; rc=$?
  n=$((n + 1)); [ "$rc" != 0 ] || fail "g-$name:exit0"
  check "g-$name-nicht-abgehakt" grep -q '^- \[ \] AC-1:' "$L"
  n=$((n + 1)); [ "$(grep -A3 '^- \[ \] AC-1:' "$L" | grep -c 'EVIDENCE: pending')" = 1 ] || fail "g-$name-nicht-pending"
done
expect g-zeit-gemeldet "$og" '*Zeit*'
expect g-rft "$(rft)" '*abgelehnt*AC-1*'

# h) Merge: AC-1 gruen, AC-2 manuell ohne Beleg → abgelehnt; Beleg nur durch acceptance-tester; dann Merge
ledger "$GUT_CHECK" "$GUT_EXPECT"
pr "$head2" '["status:in-testing","owner:acceptance-tester"]'
run > /dev/null
merge() { KIT_ROLE=product-owner "$BIN/merge.sh" 51 2>&1; }
expect h-manuell-ohne-beleg "$(merge)" '*abgelehnt*AC-2*'
expect h-attest-rolle "$(KIT_ROLE=engineer-a "$BIN/gates.sh" attest 51 AC-2 "gesehen" 2>&1)" '*acceptance-tester*'
expect h-attest-ausfuehrbar "$(KIT_ROLE=acceptance-tester "$BIN/gates.sh" attest 51 AC-1 "gesehen" 2>&1)" '*AC-1*ausfuehrbar*'
expect h-attest "$(KIT_ROLE=acceptance-tester "$BIN/gates.sh" attest 51 AC-2 "Hinweis sichtbar, Screenshot hinweis.png" 2>&1)" '*AC-2*'
check h-beleg-head grep -q "EVIDENCE: manual head=$h2 by=acceptance-tester" "$L"
expect h-merge "$(merge)" '*in-testing → done*'

observe "$((n - falsch))/$n Pruefungen bestanden · nie gelaufen, Lauf auf HEAD, neuer Push, falscher Checkout, Definition geaendert, 3 Fehlschlagarten, manuelles Gate vor Merge, attest nur acceptance-tester und nur manuell${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
