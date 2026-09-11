---
role: evals/cases/11-status-illegal-edges.sh
case: 11-status-illegal-edges
date: 2026-09-10
---
Beobachtet: Mutationsprobe — in `bin/status.sh` wurde `die "unerlaubter Uebergang …"` durch
`echo "unerlaubter Uebergang …"` ersetzt. Die Kantensperre druckte die Meldung, schrieb aber
trotzdem. Fall 11 blieb **gruen**.

Erwartet: FAIL. `protocols/LOOP.md` verlangt, dass ein unerlaubter Uebergang **abgelehnt** wird,
nicht nur gemeldet.

Ursache: **falsche Eval.** Der Fall pruefte eine Achse (die Meldung), nicht die zugesicherte (der
Zustand bleibt unveraendert). Eine zweite Fassung aus einer parallelen Session pruefte nur den
Exitcode und nur als product-owner — dort haette eine Rollensperre die Ablehnung erklaeren koennen.

Beleg: `evals/run.sh --case 11-status-illegal-edges` unter der Mutation, 2026-09-10: `PASS`.

Erledigt: beide Fassungen zusammengefuehrt. Alle 40 unerlaubten Paare, je mit der fuer das Ziel
zustaendigen Rolle, zwei Achsen: Meldung UND unveraenderte Labels. Unter derselben Mutation jetzt
`FAIL`, unmutiert `PASS 40/40`. Kein Rollenblatt geaendert.
