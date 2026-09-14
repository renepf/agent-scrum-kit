---
role: roles/_COMMON.md, bin/tick.sh, bin/common.sh, adapters/claude-code
case: praxis — Referenz-Loop, portiert als Faelle 45, 56, 57, 78
date: 2026-09-14
---
Vier Zurueckweisungen aus dem echten Betrieb eines Referenz-Loops mit acht Rollen. Keine davon hatte
das Kit abgefangen; jede ist hier als Regel oder Werkzeugpruefung plus Eval-Fall uebernommen.

1. **Rollen beendeten ihren eigenen Loop.** Bei Warnung oder STOP loeschte jede Rolle ihren Loop und
   wartete auf einen Menschen. Das Team stand drei Tage.
   Ursache: fehlende Regel. → `_COMMON.md` "Nie deinen Loop selbst beenden", Tick-Text bei Warnung und
   STOP, Hook-Text (Fall 45; Mutation Tick-Text, Hook-Zeile, Regel → rot).

2. **Eine Rolle fragte interaktiv nach und stand 299 s**, bis ein Mensch in ihr Terminal sah.
   Ursache: fehlende Regel. → `_COMMON.md` "Nie eine Rueckfrage, die auf Eingabe wartet", Hook-Text
   (Fall 45; Fall 78 live interaktiv: kein Aufruf, kein Dialog — Verhaltensbeobachtung, keine
   Mutationsprobe moeglich, weil das Modellverhalten ohne Regel nicht deterministisch ist).
   Nebenbefund: in `claude -p` steht das Rueckfrage-Werkzeug nicht zur Verfuegung; ein -p-Fall haette
   nichts gemessen und meldete deshalb BLOCK statt PASS.

3. **Ein Rollen-Anker zeigte auf eine neu vergebene PID** (einen fremden Systemprozess). `kill -0` hielt
   ihn fuer eine laufende Rolle.
   Ursache: fehlende Pruefung im Werkzeug. → `host_alive` (Adapter weiss, welcher Prozessname ein Host
   ist), in Lease, Schleife und Anker-Aufraeumen je Tick (Fall 56; Mutation Aufraeumen aus, host_alive =
   kill -0 → rot).

4. **Eine Hintergrund-Session erbte die Rolle** und wurde vom Hook als Rolle geweckt.
   Ursache: fehlende Pruefung. → `adapters/claude-code/is-background.sh` (`CLAUDE_CODE_SESSION_KIND=bg`);
   Hook schweigt, Tick endet mit Exit 3. Ausdruecklich NICHT ueber `CLAUDE_CODE_CHILD_SESSION` — die
   Variable steht in jeder Werkzeug-Umgebung und haette jede Rolle gesperrt (Fall 57; Mutation Tick ohne
   Sperre, Hook ohne Sperre, Pruefung ueber CHILD_SESSION → rot).
