#!/usr/bin/env bash
CASE_DESC="der Index wird atomar ersetzt, ein halb geschriebener Stand ist nie lesbar"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

for r in engineer-a engineer-b qa-ruthless; do
  KIT_ROLE="$r" "$BIN/say.sh" "#1 · start" <<EOF > /dev/null 2>&1
rumpf
EOF
done
"$BIN/reindex.sh" > /dev/null
voll="$(grep -c '^| [0-9]' "$SPRINT/INDEX.md")"

# Waehrend 20 Neubauten parallel laufen, wird der Index dauernd gelesen.
# Jeder Lesevorgang muss einen vollstaendigen Index sehen — nie weniger Zeilen.
for _ in $(seq 1 20); do "$BIN/reindex.sh" > /dev/null 2>&1 & done
kaputt=0; gelesen=0
for _ in $(seq 1 200); do
  n="$(grep -c '^| [0-9]' "$SPRINT/INDEX.md" 2>/dev/null || echo -1)"
  gelesen=$((gelesen + 1))
  [ "$n" = "$voll" ] || kaputt=$((kaputt + 1))
done
wait

observe "$gelesen Lesevorgaenge waehrend 20 parallelen Neubauten · unvollstaendig gelesen: $kaputt"
echo "BEOBACHTET: $OBSERVED"
[ "$kaputt" = 0 ]
