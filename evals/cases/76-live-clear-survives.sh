#!/usr/bin/env bash
CASE_DESC="interaktive Session startet ohne Eingabe in ihre Rolle und uebersteht /clear: neue Session-ID, gleiche PID, Neuregistrierung und Tick ohne Eingabe"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Kosten: zwei Modell-Runden einer Rolle (Start, nach /clear); am 2026-09-14 ~65 s.
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-clear.XXXXXX")"; trap 'rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
cat >> "$K/kit.env" <<ENV
KIT_REPO="clearprobe/projekt"
KIT_WORKTREE_ROOT="$K"
KIT_ISSUE_BACKEND="file"
ENV
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh clearprobe 9 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
res="$(python3 "$KIT_ROOT/evals/lib/clear-pty.py" "$K" "$W/screen.txt" 2>&1 | sed -n 's/^ERGEBNIS //p' | tail -1)"
[ -n "$res" ] || { echo "BEOBACHTET: BLOCKIERT — Treiber lieferte kein Ergebnis"; exit 3; }
grep -qiE 'session limit|usage limit|rate limit' "$W/screen.txt" && { echo "BEOBACHTET: BLOCKIERT — Kontingent"; exit 3; }
# Anzeige und Pruefung in EINEM Aufruf, und dicht: kann das Ergebnis nicht gelesen werden, endet
# python mit Exit != 0 und der Fall faellt durch. Vorher lief die Anzeige an einem Quoting-Fehler
# still leer, und eine unlesbare Antwort haette als "keine Fehler" gegolten.
if ! bewertung="$(printf '%s' "$res" | python3 -c '
import json, sys
r = json.load(sys.stdin)
need = {"start_ok": True, "clear_neue_id": True, "clear_neu_registriert": True, "sid1_transkript": True, "sid2_transkript": True}
f = [k for k, v in need.items() if r.get(k) is not v]
if not r.get("sid1") or r.get("sid1") == r.get("sid2"): f.append("session-id-unveraendert")
if (r.get("tick_aufrufe_nach_clear") or 0) < 1: f.append("kein-tick-nach-clear")
print("OBS Start ohne Eingabe: %s · /clear: %s -> %s · neu registriert: %s · tick nach /clear: %s" % (
    r.get("start_ok"), str(r.get("sid1"))[:8], str(r.get("sid2"))[:8], r.get("clear_neu_registriert"), r.get("tick_aufrufe_nach_clear")))
print("FEHLER " + " ".join(f))
')"; then
  echo "BEOBACHTET: Ergebnis des Treibers nicht lesbar: $(printf '%s' "$res" | cut -c1-120)"
  exit 1
fi
fehler="$(printf '%s\n' "$bewertung" | sed -n 's/^FEHLER //p')"
observe "$(printf '%s\n' "$bewertung" | sed -n 's/^OBS //p')${fehler:+ · FEHLER: $fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
