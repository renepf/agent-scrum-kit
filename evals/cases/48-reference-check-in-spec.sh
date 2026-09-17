#!/usr/bin/env bash
CASE_DESC="ist eine Referenz konfiguriert, verlangt planned in der spec.md eine REFERENCE-Zeile; ohne Referenz verlangt das Kit nichts; die Rolle nennt Referenz und Anforderungsquelle"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
pruef() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tr '\n' ' ' | head -c 120)'" ;; esac; }
plan() { KIT_ROLE=product-owner "$BIN/status.sh" 8 planned "Verdict: ok" 2>&1; }
ref() { sed -i.bak '/^KIT_REFERENCE_CMD=/d' "$SANDBOX/kit.env"; [ -z "$1" ] || echo "KIT_REFERENCE_CMD=\"$1\"" >> "$SANDBOX/kit.env"; }

sandbox_plannable 8
printf 'Verhalten: eine Datei je Lauf\n' > "$SANDBOX/tickets/8/spec.md"

# 1. Referenz konfiguriert, spec.md ohne Beleg: abgelehnt, nichts geschrieben.
ref "echo referenz-lauf"
s1="$(sandbox_snap 8)"; out="$(plan)"; s2="$(sandbox_snap 8)"
pruef a-ohne-REFERENCE "$out" '*planned abgelehnt*REFERENCE*'
n=$((n + 1)); [ "$s1" = "$s2" ] || fail "a-Zustand-veraendert"

# 2. Mit Beleg in der spec.md geht es durch.
printf 'Verhalten: eine Datei je Lauf\n\nREFERENCE: Referenzlauf 2026-09-17 11:20, Export legt eine Datei an\n' > "$SANDBOX/tickets/8/spec.md"
out="$(plan)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "b-mit-REFERENCE-abgelehnt:'$(printf '%s' "$out" | tail -1 | head -c 110)'"

# 3. Ohne konfigurierte Referenz verlangt das Kit keinen Beleg.
sandbox_plannable 9 "src/m9/**"
printf 'Verhalten: ohne Referenz\n' > "$SANDBOX/tickets/9/spec.md"
ref ""
out="$(KIT_ROLE=product-owner "$BIN/status.sh" 9 planned "Verdict: ok" 2>&1)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "c-ohne-Referenz-abgelehnt:'$(printf '%s' "$out" | tail -1 | head -c 110)'"

# 4. Rollenblatt und Beispielkonfiguration nennen beide Schluessel.
RE="$KIT_ROOT/roles/requirements-engineer.md"
n=$((n + 1)); grep -q 'KIT_REFERENCE_CMD' "$RE" || fail "d-Rolle-ohne-Referenzbefehl"
n=$((n + 1)); grep -q 'KIT_REQUIREMENTS_DIR' "$RE" || fail "e-Rolle-ohne-Anforderungsquelle"
n=$((n + 1)); grep -q '^KIT_REFERENCE_CMD=' "$KIT_ROOT/kit.env.example" || fail "f-kit.env.example-ohne-Referenzbefehl"
n=$((n + 1)); grep -q '^KIT_REQUIREMENTS_DIR=' "$KIT_ROOT/kit.env.example" || fail "g-kit.env.example-ohne-Anforderungsquelle"
# Die Rolle fuehrt die Pruefung selbst aus, in ihrer eigenen Sitzung (eiserne Regel).
n=$((n + 1)); grep -q 'in your own session' "$RE" || fail "h-Rolle-sagt-nicht-eigene-Sitzung"

observe "$n Pruefungen, $falsch falsch${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ "$falsch" = 0 ]
