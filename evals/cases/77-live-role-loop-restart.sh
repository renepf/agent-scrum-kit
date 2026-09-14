#!/usr/bin/env bash
CASE_DESC="echter Neustart unter role-loop.sh: Rolle ruft restart-self.sh, Schleife startet claude neu, neue Session registriert sich ohne Eingabe, Stopp-Datei beendet die Schleife"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Kosten: zwei Modell-Sessions einer Rolle; am 2026-09-14 ~100 s. Saubere Umgebung (Treiber).
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-restart.XXXXXX")"; trap 'pkill -f "role-loop.sh engineer-a" 2>/dev/null; rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
printf 'KIT_REPO="restartprobe/projekt"\nKIT_WORKTREE_ROOT="%s"\nKIT_ISSUE_BACKEND="file"\n' "$K" >> "$K/kit.env"
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh restartprobe 9 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
res="$(cd /tmp && python3 "$KIT_ROOT/evals/lib/restart-pty.py" "$K" "$W/screen.log" 2>&1 | sed -n 's/^ERGEBNIS //p' | tail -1)"
[ -n "$res" ] || { echo "BEOBACHTET: BLOCKIERT — Treiber lieferte kein Ergebnis"; exit 3; }
grep -qiE 'session limit|usage limit|rate limit' "$W/screen.log" && { echo "BEOBACHTET: BLOCKIERT — Kontingent"; exit 3; }
# Anzeige und Pruefung in einem Aufruf; unlesbares Ergebnis faellt durch.
if ! bewertung="$(printf '%s' "$res" | python3 -c '
import json, sys
r = json.load(sys.stdin)
f = []
for k in ("start1", "alt_beendet", "neu_registriert", "schleife_endet_mit_stopp", "neustart_im_chat"):
    if r.get(k) is not True: f.append(k)
if not r.get("pid1") or r.get("pid1") == r.get("pid2"): f.append("pid-unveraendert")
if not r.get("sid1") or r.get("sid1") == r.get("sid2"): f.append("session-id-unveraendert")
if r.get("reg2") != r.get("sid2"): f.append("registry-weicht-ab")
if r.get("anker2") != "engineer-a": f.append("anker")
if (r.get("starts_im_log") or 0) < 2: f.append("kein-zweiter-start-im-log")
print("OBS PID %s -> %s · Session %s -> %s · Starts im Log %s · Stopp beendet Schleife: %s" % (
    r.get("pid1"), r.get("pid2"), str(r.get("sid1"))[:8], str(r.get("sid2"))[:8], r.get("starts_im_log"), r.get("schleife_endet_mit_stopp")))
print("FEHLER " + " ".join(f))
')"; then
  echo "BEOBACHTET: Ergebnis des Treibers nicht lesbar: $(printf '%s' "$res" | cut -c1-120)"; exit 1
fi
fehler="$(printf '%s\n' "$bewertung" | sed -n 's/^FEHLER //p')"
observe "$(printf '%s\n' "$bewertung" | sed -n 's/^OBS //p')${fehler:+ · FEHLER: $fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
