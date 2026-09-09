---
role: evals/lib/harness.sh
case: 72/73/74-live
date: 2026-09-09
---
Beobachtet: Im Abnahmelauf fielen drei Live-Faelle durch. Der beobachtete Wert war jedes Mal
`You've hit your session limit · resets 6:10pm (Europe/Berlin)` — das Kontingent des Hosts war
erschoepft. Die Suite meldete `FAIL` und nannte die Rollen als durchgefallen.

Erwartet: Kein Urteil. Ein fehlgeschlagener Werkzeugaufruf ist ein Fehlschlag, kein Ergebnis
(`AGENTS.md`, Abschnitt "Verbot des Erfindens"). Die Suite hat aus einem Fehlschlag einen
Zustand abgeleitet — genau der Fehler, den ihre eigene Familie Anti-Halluzination verbietet.

Ursache: **fehlende Regel im Harness.** `live_claude` gab die Fehlermeldung des Hosts als
Modellantwort weiter, und die Auswertung suchte darin nach Stichworten.

Beleg: `evals/run.sh --live`, Lauf vom 2026-09-09 18:0x:
`FAIL 72-live-out-of-scope … Antwort: You've hit your session limit`

Erledigt: `live_guard` in `evals/lib/harness.sh` erkennt Kontingent-, API- und Leerantworten
und beendet den Fall mit Exitcode 3. `evals/run.sh` meldet das als **BLOCK**, zaehlt es
getrennt und gibt Exitcode 2 zurueck — unterscheidbar von 1 (echter Fehlschlag).
Gemessen mit einem vorgetaeuschten Host: `BLOCK 74-live-verification-required … EXIT=2`.
Kein Rollenblatt geaendert.
