# Evals

```bash
evals/run.sh                 # alle Faelle ohne Modellaufruf, kostenlos
evals/run.sh --live          # zusaetzlich die Faelle mit echtem Modellaufruf
evals/run.sh --gh            # zusaetzlich die Faelle mit echtem GitHub-Zugriff (liest nur)
evals/run.sh --net           # zusaetzlich die Faelle mit Paketdownloads (MCP-Handshakes)
evals/run.sh --case <name>   # genau einen Fall
evals/run.sh --list          # auflisten, nichts ausfuehren
```

Jeder Fall druckt sein Urteil **mit dem beobachteten Wert**. Ein Fall, der nur bei einem
bestimmten Host laeuft, wird als `[host-gebunden: <host>]` markiert.

| Urteil | Bedeutung | Exitcode der Suite |
|---|---|---|
| `PASS` | bestanden | |
| `FAIL` | durchgefallen | 1 |
| `BLOCK` | der Host konnte nicht antworten: Kontingent erschoepft, API-Fehler, leere Antwort | 2 |
| `SKIP` | live-Fall ohne `--live`, gh-Fall ohne `--gh`, net-Fall ohne `--net` | |

`BLOCK` ist **kein** Urteil ueber die Rolle. Ein fehlgeschlagener Aufruf ist ein Fehlschlag,
kein Ergebnis — die Suite leitet daraus keinen Zustand ab, sie sagt "erneut laufen lassen".

## Die Familien

| Praefix | Familie | Was sie prueft |
|---|---|---|
| `10–17` | Statusuebergaenge | volle Schleife backlog → done ueber `merge.sh`; alle 40 unerlaubten Kanten abgelehnt, Zustand unveraendert; Rueckwaertskante aus `in-review` und `in-testing` zurueck an den urspruenglichen Engineer; `owner:`-Besitz, `rfr`/`rft` besitzerlos; `rft`-Gate: drei PASS fuer den aktuellen HEAD; eine abgelehnte Transition schreibt nichts; product-owner hat das letzte Wort, CI frisch gemessen; Board vor Label, mit Zuruecklesen |
| `20–24` | Nebenlaeufigkeit und Index | N Sessions schreiben gleichzeitig; kein Eintrag geht verloren, der Index ist vollstaendig, deterministisch, nie halb lesbar, frei von Zwischenueberschriften und auch fuer einen leeren Sprint gueltig |
| `25–29` | Tick | ohne Sprint wird gewartet; Registrierung einmal und nach Reset erneut; jeder fremde Eintrag genau einmal, auch bei gleicher Minute; `@rolle` erreicht genau diese Rolle genau einmal; jede Rolle sieht nur ihre Warteschlange |
| `3x` | Budget | bekannte Transkripte ergeben exakt den erwarteten Kontextwert; die Schwellen loesen an der richtigen Stelle aus; fehlende Daten ergeben `UNKNOWN`, nie 0 |
| `4x` | Rollentreue (statisch) | jede Jobbeschreibung traegt die eiserne Regel woertlich, hat denselben Aufbau, kennt kein Host-Vokabular und kein Projektwissen; eine frische Kopie ist lauffaehig |
| `5x` | Anti-Halluzination (statisch) | ungeklaerte Adapter tragen `UNKNOWN`; ein fehlgeschlagener Aufruf aendert keinen Zustand; die Session-ID wird nie geraten; scheitert der Board-Aufruf oder zeigt das Board danach nichts, bleiben Label, Kommentar und Chat unveraendert |
| `6x` | Loop und Kontext-Reset | Rueckweisungen vor neuen Tickets; Zwillingssperre; neue Session holt die Uebergabe zurueck; die Rolle ueberlebt einen Reset ueber den Anker am Host-Prozess; SessionStart-Hook still ohne Rolle, weckt nur bei startup/clear/resume; Session-ID zuerst aus der Registry; `restart-self.sh` beendet nichts ohne Schleife, frische Uebergabe und Ticketgrenze; Waechter-Schleife startet neu, stoppt, gibt auf, startet keinen Zwilling; neun gleichzeitige Registrierungen ergeben neun Roster-Zeilen |
| `7x` | live | echter Modellaufruf: Adapter laedt eine Rolle, kein Subagent, Ablehnung ausserhalb des Auftrags, `UNKNOWN` statt Erfindung, kein "fertig" ohne Messung |
| `8x` | Gedaechtnis | Index generiert, eine Zeile je Eintrag, offene `[[Verweise]]` sichtbar; Dublette, relatives Datum, falscher Typ abgelehnt; falsche Fakten geloescht; geteilte Fakten aendert nur der Autor |
| `90` | Board-Check | fehlende, ueberzaehlige, falsch sortierte Optionen und fehlende Labels werden erkannt; `board.env` entsteht nur bei Erfolg |
| `91` | Board live (`--gh`) | das konfigurierte GitHub Project bildet das Statusmodell ab |
| `92` | MCP-Konfiguration | gueltiges JSON, jede Version exakt gepinnt, jeder Server durch `caveman-shrink`, jcodemunch nur auf Einschalten, Lizenzhinweis vorhanden |
| `93` | MCP live (`--net`) | jeder ausgelieferte Server antwortet auf `initialize` und `tools/list` |

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
CASE_KIND="static"        # static = kostenlos, live = Modellaufruf, gh = GitHub-Zugriff, net = Paketdownloads
CASE_HOST=""              # leer = hostunabhaengig, sonst der Hostname
```

Danach `source ../lib/harness.sh`, `sandbox` fuer eine wegwerfbare Umgebung, am Ende
`echo "BEOBACHTET: $OBSERVED"` und ein Exitcode: 0 bestanden, sonst durchgefallen.
Ein Fall prueft **nur, was in einer Jobbeschreibung oder im Protokoll steht**. Verlangt er mehr,
ist er falsch.

**Jeder neue Fall braucht eine Mutationsprobe:** die Regel, die er schuetzt, im Code abschalten →
der Fall muss rot werden. Ein Fall, der bei abgeschalteter Regel gruen bleibt, misst die falsche
Achse. Beispiel aus diesem Repo: Fall 11 pruefte nur die Fehlermeldung und blieb gruen, als die
Kantensperre die Meldung druckte und trotzdem schrieb.
