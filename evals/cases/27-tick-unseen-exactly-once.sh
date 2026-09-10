#!/usr/bin/env bash
CASE_DESC="der Tick zeigt jeden fremden Eintrag genau einmal, auch bei gleicher Minute"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
export KIT_ROLE=engineer-a

# Feste Zeitstempel, damit die Falle sicher zuschnappt: zwei Eintraege derselben Minute.
# Der Index sortiert bei Gleichstand nach Dateiname — acceptance-tester vor qa-ruthless.
# Ein Zaehler "Zeilen seit dem letzten Tick" wuerde danach den ALTEN Eintrag zeigen.
printf '# chat\n\n## 2026-01-01 10:00 · qa-ruthless · #1 · erster\nrumpf\n' > "$SPRINT/chat/qa-ruthless.md"
"$BIN/reindex.sh" > /dev/null
t1="$("$BIN/tick.sh" 2>&1)"
t2="$("$BIN/tick.sh" 2>&1)"
printf '# chat\n\n## 2026-01-01 10:00 · acceptance-tester · #1 · zweiter\nrumpf\n' > "$SPRINT/chat/acceptance-tester.md"
"$BIN/reindex.sh" > /dev/null
t3="$("$BIN/tick.sh" 2>&1)"

fehler=""
case "$t1" in *"erster"*) ;; *) fehler="$fehler Tick1-zeigt-ersten-nicht" ;; esac
case "$t2" in *"keine neuen"*) ;; *) fehler="$fehler Tick2-zeigt-erneut" ;; esac
case "$t3" in *"zweiter"*) ;; *) fehler="$fehler Tick3-zeigt-neuen-nicht" ;; esac
case "$t3" in *"erster"*) fehler="$fehler Tick3-zeigt-alten-erneut" ;; esac

observe "Tick1 zeigt 'erster' · Tick2 nichts · Tick3 nur 'zweiter' (gleiche Minute, sortiert davor)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
