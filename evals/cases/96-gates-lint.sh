#!/usr/bin/env bash
CASE_DESC="Gate-Lint gegen blinde Zeugen: planned und rft lehnen Orakel ab, die nicht fallen koennen; rft verlangt je ausfuehrbarem Gate eine QA-Zeile 'Mutation → rot'"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 140)'" ;; esac; }

# a) Regeln einzeln: Art | Titel | CHECK | EXPECT | Issue-Text (leer = "AC-1: <titel>") | Soll
while IFS='|' read -r art titel chk exp body soll; do
  [ -n "$art" ] || continue
  n=$((n + 1))
  {
    printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: %s\n' "$titel"
    [ "$art" = manuell ] || printf '  CHECK: %s\n  EXPECT: %s\n' "$chk" "$exp"
    printf '  EVIDENCE: pending\n'
  } > "$SANDBOX/lint.md"
  out="$(printf '%b\n' "${body:-AC-1: $titel}" | python3 "$BIN/gates.py" lint "$SANDBOX/lint.md" 2>&1)"; rc=$?
  case "$soll" in
    ok) [ "$rc" = 0 ] && [ -z "$out" ] || fail "a:'$chk'/'$exp'/'$titel':rc=$rc:'$(echo "$out" | head -1)'" ;;
    fehler:*) [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "^FEHLER AC-1 \[${soll#fehler:}\]" || fail "a:'$chk'/'$exp':soll=$soll:rc=$rc:'$(echo "$out" | head -1)'" ;;
    hinweis:*) [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "^HINWEIS AC-1 \[${soll#hinweis:}\]" || fail "a:'$titel':soll=$soll:rc=$rc:'$(echo "$out" | head -1)'" ;;
    *) fail "a:Tabellenzeile-ohne-Soll:'$art|$titel|$chk|$exp|$body'" ;;
  esac
done <<'TABELLE'
ausf|Export hat 3 Zeilen|echo ok|export geprueft||fehler:tautological-check
ausf|Export hat 3 Zeilen|printf 'export geprueft'|export geprueft||fehler:tautological-check
ausf|Export hat 3 Zeilen|true|export geprueft||fehler:tautological-check
ausf|Export hat 3 Zeilen|python3 tools/check.py|ok||fehler:weak-expect
ausf|Export hat 3 Zeilen|python3 tools/check.py|Bestanden||fehler:weak-expect
ausf|Export hat 3 Zeilen|python3 tools/check.py && echo fertig|fertig||fehler:weak-expect
ausf|Export hat 3 Zeilen|python3 tools/check.py|/usr/bin/app/||fehler:path-read-as-regex
ausf|Export hat 3 Zeilen|python3 tools/count.py|3|AC-1: Export hat 3 Zeilen|fehler:copied-number
ausf|Export hat 3 Zeilen|python3 tools/count.py|export zaehlt 3 zeilen||ok
ausf|Export hat 3 Zeilen|python3 tools/check.py|/export geprueft: \d+ zeilen/||ok
manuell|Hinweis ist sichtbar||||hinweis:manual-gate
manuell|Liste zeigt 3 Eintraege||||hinweis:unmeasured-number
ausf|Paywall verbessern|python3 tools/check.py|paywall geprueft||hinweis:activity-not-outcome
ausf|improve the paywall|python3 tools/check.py|paywall geprueft||hinweis:activity-not-outcome
TABELLE

# b) planned lehnt ein blindes Orakel ab und schreibt nichts
sandbox_issue 61 '{"body":"AC-1: Export hat 3 Zeilen"}'
printf '# Gates: #61\n\nOWNS: src/**\n\n- [ ] AC-1: Export hat 3 Zeilen\n  CHECK: echo export geprueft\n  EXPECT: export geprueft\n  EVIDENCE: pending\n' | sandbox_ledger 61
s1="$(sandbox_snap 61)"
expect b-planned-blind "$(KIT_ROLE=product-owner "$BIN/status.sh" 61 planned x 2>&1)" '*abgelehnt*tautological-check*'
n=$((n + 1)); [ "$s1" = "$(sandbox_snap 61)" ] || fail b:Zustand-veraendert

# c) Hinweise lehnen nicht ab und stehen im planned-Kommentar
sandbox_issue 62 '{"body":"AC-1: Export hat 3 Zeilen\nAC-2: Hinweis ist sichtbar"}'
printf '# Gates: #62\n\nOWNS: src/**\n\n- [ ] AC-1: Export hat 3 Zeilen\n  CHECK: python3 tools/check_export.py\n  EXPECT: export geprueft: 3 zeilen\n  EVIDENCE: pending\n\n- [ ] AC-2: Hinweis ist sichtbar\n  EVIDENCE: pending\n' | sandbox_ledger 62
expect c-planned-mit-hinweis "$(KIT_ROLE=product-owner "$BIN/status.sh" 62 planned x 2>&1)" '*backlog → planned*'
k62="$(KIT_ROLE=product-owner "$BIN/tickets.sh" comments 62)"
expect c-hinweis-im-kommentar "$k62" '*Lint-Hinweise*AC-2*manual-gate*'

# d) rft: CHECK nach planned zu einem festen echo abgeschwaecht und dafuer gruen gelaufen → abgelehnt
sandbox_issue 63 '{"labels":["status:in-review","owner:qa-ruthless"],"pr":{"number":630,"head":"63636363aa","comments":[],"files":["src/a.py"]}}'
sandbox_plannable 63
for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 63 "$v — HEAD \`63636363\`, eval"; done
python3 - "$SANDBOX/tickets/63/GATES.md" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("CHECK: python3 tools/check_result.py", "CHECK: echo ergebnis geprueft"))
PY
sandbox_gates_green 63
expect d-rft-abgeschwaecht "$(KIT_ROLE=qa-ruthless "$BIN/status.sh" 63 rft x 2>&1)" '*abgelehnt*tautological-check*'

# e) rft: je ausfuehrbarem Gate eine QA-Zeile "AC-<n>: Mutation … → rot" fuer den aktuellen HEAD; manuelle brauchen keine
sandbox_issue 64 '{"body":"AC-1: Export hat 3 Zeilen\nAC-2: leere Liste ergibt leere Datei\nAC-3: Hinweis ist sichtbar","labels":["status:in-review","owner:qa-ruthless"],"pr":{"number":640,"head":"64646464aa","comments":[],"files":["src/a.py"]}}'
printf '# Gates: #64\n\nOWNS: src/**\n\n- [ ] AC-1: Export hat 3 Zeilen\n  CHECK: python3 tools/check_export.py\n  EXPECT: export geprueft: 3 zeilen\n  EVIDENCE: pending\n\n- [ ] AC-2: leere Liste ergibt leere Datei\n  CHECK: python3 tools/check_empty.py\n  EXPECT: leere datei geprueft\n  EVIDENCE: pending\n\n- [ ] AC-3: Hinweis ist sichtbar\n  EVIDENCE: pending\n' | sandbox_ledger 64
sandbox_gates_green 64 nurgates
for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 64 "$v — HEAD \`64646464\`, eval"; done
rft64() { KIT_ROLE=qa-ruthless "$BIN/status.sh" 64 rft x 2>&1; }
sandbox_pr_comment 64 'QA PASS — HEAD `64646464`, 2 Tests ergaenzt'
expect e-ohne-zeilen "$(rft64)" '*abgelehnt*Mutation*AC-1*AC-2*'
sandbox_pr_comment 64 'QA PASS — HEAD `11111111`, alt
AC-1: Mutation Zeilenzaehler aus → rot
AC-2: Mutation Leerpruefung aus → rot'
expect e-alter-HEAD-zaehlt-nicht "$(rft64)" '*abgelehnt*Mutation*AC-1*AC-2*'
sandbox_pr_comment 64 'QA PASS — HEAD `64646464`, Nachtrag
AC-1: Mutation Zeilenzaehler aus → rot'
oe="$(rft64)"
expect e-nur-AC-1 "$oe" '*abgelehnt*Mutation*AC-2*'
case "$oe" in *AC-3*) fail e:manuelles-Gate-verlangt ;; esac
sandbox_pr_comment 64 'QA PASS — HEAD `64646464`, Nachtrag
AC-2: Mutation Leerpruefung aus → rot'
expect e-beide "$(rft64)" '*in-review → rft*'

observe "$((n - falsch))/$n Pruefungen bestanden · 14 Lint-Regelfaelle · planned blind abgelehnt ohne Schreibzugriff · Hinweise im Kommentar · rft nach Abschwaechung abgelehnt · QA-Zeilen: ohne, alter HEAD, unvollstaendig, vollstaendig${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
