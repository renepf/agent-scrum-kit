#!/usr/bin/env bash
CASE_DESC="eine @rolle-Ansprache erreicht genau diese Rolle, genau einmal"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

KIT_ROLE=product-owner "$BIN/say.sh" "#4 · Verdict" <<'EOF' > /dev/null 2>&1
@simplicity-reviewer bitte Loesungsweg pruefen.
EOF
KIT_ROLE=simplicity-reviewer "$BIN/say.sh" "#4 · eigene Notiz" <<'EOF' > /dev/null 2>&1
Notiz an mich selbst: @simplicity-reviewer spaeter.
EOF

a1="$(KIT_ROLE=simplicity-reviewer "$BIN/tick.sh" 2>&1)"
a2="$(KIT_ROLE=simplicity-reviewer "$BIN/tick.sh" 2>&1)"
b1="$(KIT_ROLE=security-engineer "$BIN/tick.sh" 2>&1)"

zaehle() { printf '%s' "$1" | sed -n '/direkt an dich gerichtet/,/──/p' | grep -c 'chat/' || true; }
n1="$(zaehle "$a1")"; n2="$(zaehle "$a2")"; nb="$(zaehle "$b1")"
eigene="$(printf '%s' "$a1" | sed -n '/direkt an dich gerichtet/,$p' | grep -c 'chat/simplicity-reviewer.md' || true)"

observe "simplicity-reviewer Tick1: $n1 Ansprache (eigene Datei: $eigene) · Tick2: $n2 · security-engineer: $nb"
echo "BEOBACHTET: $OBSERVED"
[ "$n1" = 1 ] && [ "$eigene" = 0 ] && [ "$n2" = 0 ] && [ "$nb" = 0 ]
