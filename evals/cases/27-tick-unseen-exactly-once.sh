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
printf '# chat\n\n## 2026-01-01 10:00 · qa-ruthless · #1 · first\nrumpf\n' > "$SPRINT/chat/qa-ruthless.md"
"$BIN/reindex.sh" > /dev/null
t1="$("$BIN/tick.sh" 2>&1)"
t2="$("$BIN/tick.sh" 2>&1)"
printf '# chat\n\n## 2026-01-01 10:00 · acceptance-tester · #1 · second\nrumpf\n' > "$SPRINT/chat/acceptance-tester.md"
"$BIN/reindex.sh" > /dev/null
t3="$("$BIN/tick.sh" 2>&1)"

fehler=""
case "$t1" in *"first"*) ;; *) fehler="$fehler tick1-does-not-show-the-first" ;; esac
case "$t2" in *"no new"*) ;; *) fehler="$fehler Tick2-zeigt-erneut" ;; esac
case "$t3" in *"second"*) ;; *) fehler="$fehler tick3-does-not-show-the-new-one" ;; esac
case "$t3" in *"first"*) fehler="$fehler tick3-shows-the-old-one-again" ;; esac

observe "tick1 shows 'first' · tick2 nothing · tick3 only 'second' (gleiche Minute, sortiert davor)${fehler:+ · FEHLER:$fehler}"
echo "OBSERVED: $OBSERVED"
[ -z "$fehler" ]
