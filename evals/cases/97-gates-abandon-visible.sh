#!/usr/bin/env bash
CASE_DESC="Weglassen nur sichtbar: ein Gate mit ABANDON blockiert Merge und done mit HANDOFF REQUIRED, bis der product-owner das AC aus Issue und Ledger nimmt; Review und Lauf ueberspringen es"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }
pr_state() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["pr"].get("state","OPEN"))' "$SANDBOX/issues.json" "$1"; }

ledger() { # <nr> <mit-abandon: ja|nein>
  {
    printf '# Gates: #%s Druckansicht\n\nOWNS: src/print/**\n\n' "$1"
    printf -- '- [ ] AC-1: Druckansicht zeigt alle Zeilen\n  CHECK: python3 tools/check_print.py\n  EXPECT: druckansicht geprueft\n  EVIDENCE: pending\n\n'
    if [ "$2" = ja ]; then
      printf -- '- [ ] AC-2: Druck landet auf dem Drucker\n  CHECK: python3 tools/check_printer.py\n  EXPECT: drucker geprueft\n  EVIDENCE: pending\n\n'
      printf 'ABANDON: AC-2 Drucker-API fehlt im Testsystem, Folgeticket #99 angelegt\n'
    fi
  } | sandbox_ledger "$1"
}

# a) Merge und done mit offenem ABANDON: abgelehnt, nichts gemergt, nichts geschrieben
sandbox_issue 81 '{"body":"AC-1: Druckansicht zeigt alle Zeilen\nAC-2: Druck landet auf dem Drucker","labels":["status:in-testing","owner:acceptance-tester"],"pr":{"number":810,"head":"81818181aa","comments":["MERGE-GATE OK — HEAD `81818181`, eval","PO OK — HEAD `81818181`, eval"],"checks":"pass","state":"OPEN","files":["src/print/view.py"]}}'
ledger 81 ja
sandbox_gates_green 81 nurgates
s1="$(sandbox_snap 81)"
expect a-merge-po "$(KIT_ROLE=product-owner "$BIN/merge.sh" 81 2>&1)" '*HANDOFF REQUIRED*AC-2*Drucker-API fehlt*'
expect a-merge-gate "$(KIT_ROLE=merge-gate "$BIN/merge.sh" 81 2>&1)" '*HANDOFF REQUIRED*AC-2*'
expect a-done-direkt "$(KIT_ROLE=product-owner "$BIN/status.sh" 81 done x 2>&1)" '*HANDOFF REQUIRED*AC-2*'
n=$((n + 1)); [ "$(pr_state 81)" = OPEN ] || fail "a:PR-gemergt-trotz-ABANDON($(pr_state 81))"
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 81)" ] || fail a:Zustand-veraendert

# b) Review blockiert es nicht: rft ohne Beleg und ohne QA-Zeile fuer das aufgegebene Gate
sandbox_issue 82 '{"body":"AC-1: Druckansicht zeigt alle Zeilen\nAC-2: Druck landet auf dem Drucker","labels":["status:in-review","owner:qa-ruthless"],"pr":{"number":820,"head":"82828282aa","comments":["SIMPLICITY PASS — HEAD `82828282`, eval","SECURITY PASS — HEAD `82828282`, eval","QA PASS — HEAD `82828282`, eval\nAC-1: Mutation Zeilenzaehler aus → rot"],"files":["src/print/view.py"]}}'
ledger 82 ja
sandbox_gates_green 82 nurgates
python3 - "$SANDBOX/tickets/82/GATES.md" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
head, sep, rest = t.partition("- [x] AC-2:")
rest = re.sub(r"EVIDENCE: .*", "EVIDENCE: pending", rest, count=1)
open(p, "w").write(head + "- [ ] AC-2:" + rest)
PY
expect b-rft-ueberspringt "$(KIT_ROLE=qa-ruthless "$BIN/status.sh" 82 rft x 2>&1)" '*in-review → rft*'

# c) Der Lauf ueberspringt ein aufgegebenes Gate, auch wenn sein CHECK scheitern wuerde
P="$SANDBOX/lauf"; mkdir -p "$P"
printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: Zeilen gezaehlt\n  CHECK: python3 -c "print(chr(122)+\\"eilen gezaehlt\\")"\n  EXPECT: zeilen gezaehlt\n  EVIDENCE: pending\n\n- [ ] AC-2: Drucker erreicht\n  CHECK: python3 -c "import sys; sys.exit(3)"\n  EXPECT: drucker erreicht\n  EVIDENCE: pending\n\nABANDON: AC-2 kein Drucker im Testsystem\n' > "$P/GATES.md"
oc="$(python3 "$BIN/gates.py" run "$P/GATES.md" 83838383 "$P" engineer-a 30 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "c:rc=$rc:'$(echo "$oc" | tr '\n' ' ' | head -c 120)'"
case "$oc" in *AC-2*) fail "c:AC-2-gelaufen" ;; esac
expect c-AC-1-gruen "$oc" '*AC-1 gruen*'

# d) Das letzte Wort hat der product-owner: AC-2 per Folgeticket aus Issue und Ledger genommen → Merge geht durch
sandbox_issue 81 '{"body":"AC-1: Druckansicht zeigt alle Zeilen\n\nDruck auf dem Drucker: Folgeticket #99"}'
ledger 81 nein
sandbox_gates_green 81 nurgates
expect d-merge-nach-entscheid "$(KIT_ROLE=product-owner "$BIN/merge.sh" 81 2>&1)" '*in-testing → done*'

observe "$((n - falsch))/$n Pruefungen bestanden · Merge (PO, merge-gate) und done mit ABANDON abgelehnt, PR offen, nichts geschrieben · rft ueberspringt · Lauf ueberspringt · nach Entscheid des PO gemergt${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
