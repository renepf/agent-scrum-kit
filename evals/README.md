# Evals

```bash
evals/run.sh                 # alle Faelle ohne Modellaufruf, kostenlos
evals/run.sh --live          # zusaetzlich die Faelle mit echtem Modellaufruf
evals/run.sh --case <name>   # genau einen Fall
evals/run.sh --list          # auflisten, nichts ausfuehren
```

Jeder Fall druckt bestanden oder durchgefallen **mit dem beobachteten Wert**. Ein Fall, der
nur bei einem bestimmten Host laeuft, wird als `[host-gebunden: <host>]` markiert.

## Die Familien

| Praefix | Familie | Was sie prueft |
|---|---|---|
| `1x` | Statusuebergaenge | jede erlaubte Kante funktioniert, jede unerlaubte wird abgelehnt, die Rueckwaertskante fuehrt aus jedem Pruefzustand auf `in-progress` und die volle Schleife laeuft erneut |
| `2x` | Nebenlaeufigkeit | N Sessions schreiben gleichzeitig; kein Eintrag geht verloren, der Index ist vollstaendig, deterministisch und nie halb lesbar |
| `3x` | Budget | bekannte Transkripte ergeben exakt den erwarteten Kontextwert; die Schwellen loesen an der richtigen Stelle aus; fehlende Daten ergeben `UNKNOWN`, nie 0 |
| `4x` | Rollentreue (statisch) | jede Jobbeschreibung traegt die eiserne Regel woertlich, hat denselben Aufbau, kennt kein Host-Vokabular und kein Projektwissen |
| `5x` | Anti-Halluzination (statisch) | ungeklaerte Adapter tragen `UNKNOWN` statt eines Platzhalters; ein fehlgeschlagener Aufruf aendert keinen Zustand |
| `7x` | live | echter Modellaufruf: Adapter laedt eine Rolle, kein Subagent, Ablehnung ausserhalb des Auftrags, `UNKNOWN` statt Erfindung, kein "fertig" ohne Messung |

Die Live-Familie misst "kein Subagent" nicht am Text, sondern an `subagent_stats.spawned`
aus dem Ergebnis des Hosts. Eine Absichtserklaerung im Antworttext zaehlt nicht.

## Der geschlossene Kreis

1. Faellt eine Rolle in einer Eval durch, oder wird ihre Arbeit in der Praxis zurueckgewiesen,
   schreibt der **watchdog** den Fall nach `evals/findings/`.
2. Der **kit-maintainer** macht daraus einen **Pull Request** an der Jobbeschreibung, mit dem
   fehlgeschlagenen Fall als Beleg.
3. Ein **Mensch** merged. Eine Rolle aendert ihre eigene Jobbeschreibung niemals selbst.

Jede Aenderung an einer Jobbeschreibung muss mindestens einen zuvor durchgefallenen Fall
bestehen lassen, ohne einen bestehenden zu brechen. Beide Laeufe gehoeren in den PR-Text:

```bash
evals/run.sh --case <der-fall>   # vorher FAIL, nachher PASS
evals/run.sh                     # kein bestehender Fall bricht
```

Drei Antworten sind auf einen durchgefallenen Fall moeglich, und alle drei sind erlaubt:
eine fehlende Regel, eine mehrdeutige Regel — oder **eine falsche Eval**. Ein Beispiel fuer
den dritten Fall liegt in `evals/findings/`.

## Einen Fall hinzufuegen

Eine Datei `evals/cases/<nn>-<name>.sh` mit drei Kopfzeilen:

```bash
CASE_DESC="was der Fall prueft"
CASE_KIND="static"        # static = kostenlos, live = echter Modellaufruf
CASE_HOST=""              # leer = hostunabhaengig, sonst der Hostname
```

Danach `source ../lib/harness.sh`, `sandbox` fuer eine wegwerfbare Umgebung, am Ende
`echo "BEOBACHTET: $OBSERVED"` und ein Exitcode: 0 bestanden, sonst durchgefallen.
Ein Fall prueft **nur, was in einer Jobbeschreibung steht**. Verlangt er mehr, ist er falsch.
