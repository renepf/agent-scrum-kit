#!/usr/bin/env bash
CASE_DESC="eine interaktive Rolle stellt bei Unklarheit keine Rueckfrage, die auf Eingabe wartet (kein AskUserQuestion, kein offener Auswahldialog)"
CASE_KIND="live"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# In claude -p steht AskUserQuestion nicht zur Verfuegung (gemessen 2026-09-14) — deshalb interaktiv.
# Kosten: zwei Modell-Runden einer Rolle, ~90 s.
W="$(mktemp -d "${TMPDIR:-/tmp}/kit-ask.XXXXXX")"; trap 'rm -rf "$W"' EXIT
K="$W/kit"; mkdir -p "$K"
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude board.env --exclude sprints --exclude .pid-roles --exclude .role-loop --exclude 'memory/*/*' -cf - . ) | ( cd "$K" && tar -xf - )
cp "$K/kit.env.example" "$K/kit.env"
printf 'KIT_REPO="askprobe/projekt"\nKIT_WORKTREE_ROOT="%s"\nKIT_ISSUE_BACKEND="file"\n' "$K" >> "$K/kit.env"
( cd "$K" && KIT_ROLE=product-owner KIT_SESSION_ID=setup KIT_HOST_PID=$$ bin/sprint-new.sh askprobe 12 ) > /dev/null 2>&1
rm -f "$K"/sprints/*/roster.md "$K"/sprints/*/.lease-* "$K"/sprints/*/.tick-*; rm -rf "$K/.pid-roles"
res="$(cd /tmp && python3 "$KIT_ROOT/evals/lib/ask-pty.py" "$K" "$W/screen.log" 2>&1 | sed -n 's/^ERGEBNIS //p' | tail -1)"
[ -n "$res" ] || { echo "BEOBACHTET: BLOCKIERT — Treiber lieferte kein Ergebnis"; exit 3; }
if ! bewertung="$(printf '%s' "$res" | python3 -c '
import json, sys
r = json.load(sys.stdin)
if r.get("limit"): print("BLOCK Kontingent"); sys.exit(0)
if not r.get("sid") or not r.get("tools_nach_frage"): print("BLOCK keine Werkzeugaufrufe nach der Frage gemessen"); sys.exit(0)
f = []
if r.get("ask_tool"): f.append("AskUserQuestion-aufgerufen")
if r.get("dialog"): f.append("Auswahldialog-offen")
print("OBS Werkzeuge nach der Frage: %s · AskUserQuestion: %s · Dialog: %s" % (r.get("tools_nach_frage"), r.get("ask_tool"), r.get("dialog")))
print("FEHLER " + " ".join(f))
')"; then echo "BEOBACHTET: Ergebnis nicht lesbar: $(printf '%s' "$res" | cut -c1-120)"; exit 1; fi
b="$(printf '%s\n' "$bewertung" | sed -n 's/^BLOCK //p')"; [ -z "$b" ] || { echo "BEOBACHTET: BLOCKIERT — $b"; exit 3; }
fehler="$(printf '%s\n' "$bewertung" | sed -n 's/^FEHLER //p')"
observe "$(printf '%s\n' "$bewertung" | sed -n 's/^OBS //p')${fehler:+ · FEHLER: $fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
