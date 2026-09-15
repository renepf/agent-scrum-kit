#!/usr/bin/env bash
CASE_DESC="planned verlangt ein Ledger, das jede AC-<n> des Issues mit einem Gate deckt; eine Ablehnung schreibt nichts"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_issue 31 '{"body":"Als Nutzer moechte ich meine Liste exportieren.\n\n1. AC-1: Export legt eine Datei an\n2. AC-2: eine leere Liste ergibt eine leere Datei\n3. AC-3: ein Schreibfehler erscheint als Meldung"}'
plan() { KIT_ROLE=product-owner "$BIN/status.sh" "$1" planned "Verdict: ok" 2>&1; }
snap() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]], sort_keys=True))' "$SANDBOX/issues.json" "$1"; }
gate() {
  printf -- '- [ ] %s: %s\n  CHECK: python3 tools/check_export.py %s\n  EXPECT: export geprueft %s\n  EVIDENCE: pending\n\n' "$1" "$2" "$1" "$1"
}
vorher="$(snap 31)"; fehler=""

# a) kein Ledger
oa="$(plan 31)"; case "$oa" in *"kein Ledger"*) ;; *) fehler="$fehler a:ohne-Ledger-durch:'$(echo "$oa" | tail -1)'" ;; esac

# b) Ledger deckt AC-3 nicht
{ echo "# Gates: #31 Export"; echo; gate AC-1 "Datei entsteht"; gate AC-2 "leere Datei"; } | sandbox_ledger 31
ob="$(plan 31)"; case "$ob" in *"ohne Gate"*"AC-3"*) ;; *) fehler="$fehler b:fehlendes-AC-durch:'$(echo "$ob" | tail -1)'" ;; esac

# c) Ledger nennt ein AC, das das Issue nicht kennt (Tippfehler)
{ echo "# Gates: #31 Export"; echo; gate AC-1 "Datei entsteht"; gate AC-2 "leere Datei"; gate AC-3 "Meldung"; gate AC-9 "gibt es nicht"; } | sandbox_ledger 31
oc="$(plan 31)"; case "$oc" in *"AC-9"*) ;; *) fehler="$fehler c:unbekanntes-AC-durch:'$(echo "$oc" | tail -1)'" ;; esac

# d) formal kaputt: ausfuehrbares Gate ohne EXPECT
{ echo "# Gates: #31 Export"; echo; printf -- '- [ ] AC-1: Datei entsteht\n  CHECK: python3 tools/check_export.py\n  EVIDENCE: pending\n\n'; gate AC-2 "leere Datei"; gate AC-3 "Meldung"; } | sandbox_ledger 31
od="$(plan 31)"; case "$od" in *"AC-1"*"CHECK und EXPECT"*) ;; *) fehler="$fehler d:kaputtes-Ledger-durch:'$(echo "$od" | tail -1)'" ;; esac

nach="$(snap 31)"
[ "$vorher" = "$nach" ] || fehler="$fehler Zustand-nach-Ablehnung-veraendert"

# e) Issue ohne AC-Zeilen: nichts, woran ein Gate haengen kann
sandbox_issue 32 '{"body":"Irgendwas soll besser werden."}'
{ echo "# Gates: #32"; echo; gate AC-1 "irgendwas"; } | sandbox_ledger 32
oe="$(plan 32)"; case "$oe" in *"keine AC"*) ;; *) fehler="$fehler e:Issue-ohne-AC-durch:'$(echo "$oe" | tail -1)'" ;; esac

# f) Gegenprobe: vollstaendiges Ledger
{ echo "# Gates: #31 Export"; echo; gate AC-1 "Datei entsteht"; gate AC-2 "leere Datei"; gate AC-3 "Meldung"; } | sandbox_ledger 31
of="$(plan 31)"; case "$of" in *"backlog → planned"*) ;; *) fehler="$fehler f:vollstaendig-abgelehnt:'$(echo "$of" | tail -1)'" ;; esac

observe "ohne Ledger → abgelehnt · AC-3 ohne Gate → abgelehnt · AC-9 unbekannt → abgelehnt · CHECK ohne EXPECT → abgelehnt · Zustand byte-gleich: $([ "$vorher" = "$nach" ] && echo ja || echo NEIN) · Issue ohne AC → abgelehnt · vollstaendig → $(echo "$of" | tail -1)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
