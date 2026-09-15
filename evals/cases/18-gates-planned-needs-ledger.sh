#!/usr/bin/env bash
CASE_DESC="planned verlangt ein Ledger, das jede AC-<n> des Issues in jeder Schreibweise mit einem Gate deckt und frisch beginnt; eine Ablehnung schreibt nichts"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 120)'" ;; esac; }
plan() { KIT_ROLE=product-owner "$BIN/status.sh" "$1" planned "Verdict: ok" 2>&1; }
# Abgelehnt mit Meldung, und weder Issue noch tickets/<nr>/ haben sich veraendert.
abgelehnt() {
  local s1 s2 out
  s1="$(sandbox_snap "$2")"; out="$(plan "$2")"; s2="$(sandbox_snap "$2")"
  expect "$1" "$out" "$3"
  [ "$s1" = "$s2" ] || fail "$1:Zustand-veraendert"
}
kopf() { printf '# Gates: #31 Export\n\nOWNS: src/export/**\n\n'; }
gate() { printf -- '- [ ] %s: %s\n  CHECK: python3 tools/check_export.py %s\n  EXPECT: export geprueft %s\n  EVIDENCE: pending\n\n' "$1" "$2" "$1" "$1"; }

sandbox_issue 31 '{"body":"Als Nutzer moechte ich meine Liste exportieren.\n\n1. AC-1: Export legt eine Datei an\n2. AC-2: eine leere Liste ergibt eine leere Datei\n3. AC-3: ein Schreibfehler erscheint als Meldung"}'

abgelehnt a-ohne-Ledger 31 '*kein Ledger*'
{ kopf; gate AC-1 datei; gate AC-2 leer; } | sandbox_ledger 31
abgelehnt b-AC-ohne-Gate 31 '*ohne Gate*AC-3*'
{ kopf; gate AC-1 datei; gate AC-2 leer; gate AC-3 meldung; gate AC-9 gibt-es-nicht; } | sandbox_ledger 31
abgelehnt c-unbekannte-AC 31 '*AC-9*'
{ kopf; printf -- '- [ ] AC-1: datei\n  CHECK: python3 tools/check_export.py\n  EVIDENCE: pending\n\n'; gate AC-2 leer; gate AC-3 meldung; } | sandbox_ledger 31
abgelehnt d-CHECK-ohne-EXPECT 31 '*AC-1*CHECK und EXPECT*'
{ kopf; printf -- '- [x] AC-1: datei\n  CHECK: python3 tools/check_export.py AC-1\n  EXPECT: export geprueft AC-1\n  EVIDENCE: pending\n\n'; gate AC-2 leer; gate AC-3 meldung; } | sandbox_ledger 31
abgelehnt e-schon-abgehakt 31 '*abgehakt*AC-1*'
{ kopf; gate AC-1 datei; gate AC-2 leer; gate AC-3 meldung; printf 'ABANDON: AC-3 zu teuer\n'; } | sandbox_ledger 31
abgelehnt f-ABANDON-vorab 31 '*ABANDON*AC-3*'
sandbox_issue 32 '{"body":"Irgendwas soll besser werden."}'
{ printf '# Gates: #32\n\nOWNS: src/**\n\n'; gate AC-1 irgendwas; } | sandbox_ledger 32
abgelehnt g-Issue-ohne-AC 32 '*keine AC*'

# h) AC-Schreibweisen: jede zaehlt; in einem Code-Zaun oder HTML-Kommentar keine.
#    Das Ledger deckt nur AC-1 — also muss jedes Issue mit einer weiteren AC abgelehnt werden.
printf '# Gates\n\nOWNS: src/**\n\n- [ ] AC-1: a\n  CHECK: python3 tools/check_a.py\n  EXPECT: a gemessen\n  EVIDENCE: pending\n' > "$SANDBOX/nur-ac1.md"
while IFS=';' read -r name text soll; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  printf '%b' "$text" | python3 "$BIN/gates.py" planned "$SANDBOX/nur-ac1.md" > /dev/null 2>&1 && ist=durch || ist=abgelehnt
  [ "$ist" = "$soll" ] || fail "h-$name:$ist"
done <<'TABELLE'
zeile;AC-1: a\nAC-2: b;abgelehnt
checkbox;AC-1: a\n- [ ] AC-2: b;abgelehnt
ueberschrift;AC-1: a\n### AC-2: b;abgelehnt
zitat;AC-1: a\n> AC-2: b;abgelehnt
tabelle;AC-1: a\n| AC-2 | b |;abgelehnt
fett;AC-1: a\n**AC-2** — b;abgelehnt
crlf;AC-1: a\r\nAC-2: b\r\n;abgelehnt
nur-ac1;1. AC-1: a;durch
code-zaun;AC-1: a\n```\nAC-2: b\n```;durch
html-kommentar;<!--\nAC-2: <ergebnis>\n-->\nAC-1: a;durch
TABELLE

# i) Gegenprobe: vollstaendiges, frisches Ledger
{ kopf; gate AC-1 datei; gate AC-2 leer; gate AC-3 meldung; } | sandbox_ledger 31
oi="$(plan 31)"
expect i-vollstaendig "$oi" '*backlog → planned*'

observe "$((n - falsch))/$n Pruefungen bestanden · 7 Ablehnungen mit Byte-Vergleich von Issue und tickets/<nr>/ · 10 AC-Schreibweisen · Gegenprobe: $(echo "$oi" | tail -1)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
