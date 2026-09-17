#!/usr/bin/env bash
CASE_DESC="planned verlangt die Artefaktkette intent.md, spec.md, plan.md je Ticket; jedes fehlende oder leere Glied wird einzeln benannt, eine Ablehnung schreibt nichts; der requirements-engineer ist im Cast und nimmt backlog auf"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

n=0; falsch=0; fehler=""
fail() { falsch=$((falsch + 1)); fehler="$fehler $*"; }
expect() { n=$((n + 1)); case "$2" in $3) ;; *) fail "$1:'$(printf '%s' "$2" | tail -1 | head -c 110)'" ;; esac; }
plan() { KIT_ROLE=product-owner "$BIN/status.sh" 7 planned "Verdict: ok" 2>&1; }
art() { printf '%s\n' "${2-inhalt}" > "$SANDBOX/tickets/7/$1"; }   # ${2-...}: eine leere Zeichenkette bleibt leer
abgelehnt() {
  local s1 s2 out
  s1="$(sandbox_snap 7)"; out="$(plan)"; s2="$(sandbox_snap 7)"
  expect "$1" "$out" "$2"
  [ "$s1" = "$s2" ] || fail "$1:Zustand-veraendert"
}

sandbox_plannable 7
rm -f "$SANDBOX/tickets/7/intent.md" "$SANDBOX/tickets/7/spec.md" "$SANDBOX/tickets/7/plan.md"

# Die Kette wird Glied fuer Glied benannt, nicht als Sammelmeldung: intent.md zuerst.
abgelehnt a-ohne-intent '*planned abgelehnt*intent.md*'
art intent.md "Problem: der Export fehlt"
abgelehnt b-ohne-spec '*planned abgelehnt*spec.md*'
art spec.md "Verhalten: eine Datei je Lauf"
abgelehnt c-ohne-plan '*planned abgelehnt*plan.md*'
# Eine leere Datei ist kein Artefakt.
art plan.md ""
abgelehnt d-plan-leer '*planned abgelehnt*plan.md*'

art plan.md "Schritte: 1. Modul, 2. Test"
out="$(plan)"; rc=$?
n=$((n + 1)); [ "$rc" = 0 ] || fail "e-vollstaendig-abgelehnt:'$(printf '%s' "$out" | tail -1 | head -c 110)'"
n=$((n + 1)); case "$(sandbox_labels 7)" in *"status:planned"*) ;; *) fail "e-kein-Label:'$(sandbox_labels 7)'" ;; esac

# Verdrahtung: die Rolle existiert, steht im Cast und nimmt backlog auf.
n=$((n + 1)); [ -f "$KIT_ROOT/roles/requirements-engineer.md" ] || fail "f-Rollendatei-fehlt"
n=$((n + 1)); grep -q '^KIT_ROLES=.*requirements-engineer' "$KIT_ROOT/kit.env.example" || fail "g-nicht-in-KIT_ROLES"
n=$((n + 1)); grep -q '^requirements-engineer|backlog' "$KIT_ROOT/kit.env.example" || fail "h-keine-Warteschlange"
n=$((n + 1)); grep -q 'requirements-engineer' "$KIT_ROOT/protocols/LOOP.md" || fail "i-nicht-im-Cast-des-Protokolls"

observe "$n Pruefungen, $falsch falsch${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ "$falsch" = 0 ]
