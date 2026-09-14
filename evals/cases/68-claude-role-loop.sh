#!/usr/bin/env bash
CASE_DESC="Waechter-Schleife: startet neu, endet mit Stopp-Datei, gibt nach 3 schnellen Abbruechen auf, startet keinen Zwilling"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$LEBT" 2>/dev/null; rm -rf "$KIT_ROOT/.role-loop" "$KIT_ROOT/.pid-roles/$LEBT"; sandbox_cleanup' EXIT
L="$KIT_ROOT/adapters/claude-code/role-loop.sh"; ST="$KIT_ROOT/.role-loop"
fehler=""
rm -rf "$ST"
# A: drei schnelle Abbrueche → Schleife gibt auf, Exit 1
KIT_LOOP_CLAUDE='true' KIT_LOOP_SLEEP=0 "$L" merge-gate > /dev/null 2>&1; ra=$?
starts="$(grep -c 'starte claude' "$ST/merge-gate.log")"
[ "$ra" = 1 ] && [ "$starts" = 3 ] || fehler="$fehler A:rc=$ra,starts=$starts"
# B: Stopp-Datei nach dem zweiten Start → Schleife endet sauber
cnt="$SANDBOX/cnt"; : > "$cnt"
KIT_LOOP_CLAUDE="echo x >> '$cnt'; [ \$(wc -l < '$cnt') -ge 2 ] && touch '$ST/qa-ruthless.stop'; true" KIT_LOOP_SLEEP=0 "$L" qa-ruthless > /dev/null 2>&1; rb=$?
[ "$rb" = 0 ] && [ "$(wc -l < "$cnt" | tr -d ' ')" = 2 ] || fehler="$fehler B:rc=$rb,starts=$(wc -l < "$cnt")"
grep -q 'Stopp-Datei gefunden' "$ST/qa-ruthless.log" || fehler="$fehler B:log"
# C: Umgebung in der Schleife: KIT_ROLE und KIT_ROLE_LOOP
envf="$SANDBOX/env"
KIT_LOOP_CLAUDE="echo \"\$KIT_ROLE \$KIT_ROLE_LOOP\" > '$envf'; touch '$ST/watchdog.stop'" KIT_LOOP_SLEEP=0 "$L" watchdog > /dev/null 2>&1
[ "$(cat "$envf")" = "watchdog 1" ] || fehler="$fehler C:env='$(cat "$envf")'"
# D: lebender Anker derselben Rolle → kein zweiter Start
sleep 300 & LEBT=$!; mkdir -p "$KIT_ROOT/.pid-roles"; echo engineer-a > "$KIT_ROOT/.pid-roles/$LEBT"
od="$(KIT_LOOP_CLAUDE='echo GESTARTET' "$L" engineer-a 2>&1)"; rd=$?
[ "$rd" != 0 ] && case "$od" in *"laeuft schon"*) true ;; *) false ;; esac || fehler="$fehler D:'$od'"
case "$od" in *GESTARTET*) fehler="$fehler D:zwilling-gestartet" ;; esac
observe "A: 3 Starts, Exit $ra · B: Stopp nach 2 Starts, Exit $rb · C: Umgebung '$(cat "$envf")' · D: Zwilling abgewiesen (Exit $rd)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
