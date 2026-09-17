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
| `18` | Gate-Ledger | `planned` nur mit Ledger, das jede AC des Issues deckt und frisch beginnt; fehlendes oder kaputtes Ledger, unbekannte AC, abgehaktes Gate, `ABANDON` vorab und ein Issue ohne AC werden abgelehnt, mit Byte-Vergleich von Issue und `tickets/<nr>/`; zehn AC-Schreibweisen samt Code-Zaun und HTML-Kommentar |
| `19` | Umfang | `planned` verlangt `OWNS:` und haelt es als Revision 1 am Issue fest; `rfr` lehnt eine PR-Datei ausserhalb ab, auch den alten Pfad einer Umbenennung; eigene OWNS-Erweiterung und fremde Freigabezeilen zaehlen nicht; sechs unzulaessige Revisionen; Revision 2 nur durch den product-owner; ohne PR, mit zwei PRs, leerer oder unlesbarer Dateiliste keine Abgabe; 14 Glob-Formen; gh-Pfad ueber vorgetaeuschtes gh |
| `20–24` | Nebenlaeufigkeit und Index | N Sessions schreiben gleichzeitig; kein Eintrag geht verloren, der Index ist vollstaendig, deterministisch, nie halb lesbar, frei von Zwischenueberschriften und auch fuer einen leeren Sprint gueltig |
| `25–29` | Tick | ohne Sprint wird gewartet; Registrierung einmal und nach Reset erneut; jeder fremde Eintrag genau einmal, auch bei gleicher Minute; `@rolle` erreicht genau diese Rolle genau einmal; jede Rolle sieht nur ihre Warteschlange |
| `3x` | Budget | bekannte Transkripte ergeben exakt den erwarteten Kontextwert; die Schwellen loesen an der richtigen Stelle aus; fehlende Daten ergeben `UNKNOWN`, nie 0 |
| `35` | Kein Modell ohne Arbeit | `bin/tick.sh --signal` meldet mit Exit 4, dass nichts anliegt, ohne Schalter bleibt es bei 0; die Waechter-Schleife startet dann kein Modell; ein Statuswechsel weckt genau die Rollen, die den neuen Zustand aufnehmen; eine Weckmarke ohne Arbeit startet nichts |
| `34` | Budget per host | qwen-code (`usageMetadata.promptTokenCount`, cache included) and pi (`input + cacheRead + cacheWrite`) transcripts give the exact context value, the largest turn and not the sum; a transcript without a usage record the kit knows is `UNKNOWN`, never 0 |
| `4x` | Rollentreue (statisch) | jede Jobbeschreibung traegt die eiserne Regel woertlich, hat denselben Aufbau, kennt kein Host-Vokabular und kein Projektwissen; eine frische Kopie ist lauffaehig; den eigenen Loop nie beenden und keine blockierende Rueckfrage — im Blatt, im Tick-Text und im Hook (45) |
| `54` | Local host transcripts | the qwen-code and pi adapters print exactly the transcript of the given session id (paths measured against qwen 0.23.4 and pi 0.85.1), never the newest file of another session, and fail for an unknown id |
| `58` | Local model check | against a stub endpoint: a structured tool call is `yes`, a call written as text is `no`, a failed request and an unreachable endpoint are `UNKNOWN`; exit 0 only when `KIT_LOCAL_MODEL` is set and passed |
| `59` | Neustart ohne Schleife | zellij-Weg: Tab mit `role-loop.sh --after`, Beenden erst bei laufender Schleife, Schleife wartet auf das Ende; scheitert der Tab, wird nichts beendet |
| `46` | Artefaktkette | `planned` lehnt ab, solange `tickets/<nr>/intent.md`, `spec.md` oder `plan.md` fehlt oder leer ist, benennt das fehlende Glied einzeln und schreibt bei Ablehnung nichts; der `requirements-engineer` steht im Cast und nimmt `backlog` auf |
| `47` | Planungssignale | `sprint-new.sh` lehnt ein Ticket ohne vollstaendige Artefaktkette ab und legt nichts an; der Tick zeigt dem `requirements-engineer` die Luecken im `backlog` mit den fehlenden Dateien und dem `product-owner` die Kanban-Zahlen samt Planungsstopp, anderen Rollen nicht |
| `48` | Referenzbefund | ist `KIT_REFERENCE_CMD` gesetzt, lehnt `planned` eine `spec.md` ohne `REFERENCE:`-Zeile ab und schreibt nichts; mit Zeile geht es durch; ohne konfigurierte Referenz verlangt das Kit nichts; das Rollenblatt nennt beide Schluessel und die eigene Sitzung |
| `49` | Local host start | `adapters/qwen-code/start.sh` and `adapters/pi/start.sh` against fake hosts and a stub endpoint: a model without tool calls starts nothing; a passing model execs the host with the measured flags, the same PID and a fresh session id; pi also needs its `kit-local` provider pointing at the endpoint; `session-id.sh` and `host-pid.sh` print the start values or fail; `host-alive.sh` tells the host from another process |
| `79` | Local hosts live (`--live`) | with the model from `kit.env` passing `bin/local-model-check.sh`, qwen-code and pi each run a shell command that sees `KIT_SESSION_ID`, and both transcripts are found; otherwise `BLOCK` |
| `5x` | Anti-Halluzination (statisch) | ungeklaerte Adapter tragen `UNKNOWN`; ein fehlgeschlagener Aufruf aendert keinen Zustand; die Session-ID wird nie geraten; scheitert der Board-Aufruf oder zeigt das Board danach nichts, bleiben Label, Kommentar und Chat unveraendert; eine neu vergebene PID gilt nicht als Rolle (56); eine Hintergrund-Session mit geerbter Rolle tickt nicht (57) |
| `6x` | Loop und Kontext-Reset | Rueckweisungen vor neuen Tickets; Zwillingssperre; neue Session holt die Uebergabe zurueck; die Rolle ueberlebt einen Reset ueber den Anker am Host-Prozess; SessionStart-Hook still ohne Rolle, weckt nur bei startup/clear/resume; Session-ID zuerst aus der Registry; `restart-self.sh` beendet nichts ohne Schleife, frische Uebergabe und Ticketgrenze; Waechter-Schleife startet neu, stoppt, gibt auf, startet keinen Zwilling; neun gleichzeitige Registrierungen ergeben neun Roster-Zeilen |
| `7x` | live | echter Modellaufruf: Adapter laedt eine Rolle, kein Subagent, Ablehnung ausserhalb des Auftrags, `UNKNOWN` statt Erfindung, kein "fertig" ohne Messung; neun Sessions starten parallel (75); Rolle uebersteht `/clear` (76); echter Selbst-Neustart unter `role-loop.sh` (77); interaktive Rolle stellt bei Unklarheit keine blockierende Rueckfrage (78, Verhaltensbeobachtung ohne Mutationsprobe) |
| `8x` | Gedaechtnis | Index generiert, eine Zeile je Eintrag, offene `[[Verweise]]` sichtbar; Dublette, relatives Datum, falscher Typ abgelehnt; falsche Fakten geloescht; geteilte Fakten aendert nur der Autor |
| `94` | Kein Ueberlappen | `planned`, `revise.sh` und `sprint-new.sh` lehnen OWNS ab, die sich mit einem freigegebenen Ticket desselben Sprints ueberschneiden; 11 Glob-Paare; anderer Sprint und fehlende Freigabe zaehlen nicht; kein Sprint bei Ablehnung; gh-Pfad mit unlesbaren Kommentaren |
| `95` | Gruen fuer HEAD | `rft` erst, wenn jedes ausfuehrbare Gate fuer den aktuellen HEAD gruen lief (echter Lauf in einem Git-Sandkasten); neuer Push, falscher Checkout und geaenderte Definition machen den Beleg ungueltig; Exit 0 ohne EXPECT, EXPECT mit Exit 1 und Zeitueberschreitung sind rot; Merge verlangt Belege fuer manuelle Gates, nur vom acceptance-tester, nur fuer manuelle Gates. Braucht eine Git-Identitaet in `~/.gitconfig` |
| `96` | Gate-Lint | 14 Regelfaelle (fester Ausgabebefehl, schwaches EXPECT auch deutsch, Pfad als Regex, kopierte Zahl, Hinweise); `planned` lehnt ein blindes Orakel ohne Schreibzugriff ab und schreibt Hinweise in den Kommentar; `rft` lehnt ein nach planned abgeschwaechtes CHECK ab; `rft` verlangt je ausfuehrbarem Gate eine QA-Mutationszeile fuer den aktuellen HEAD |
| `97` | Weglassen sichtbar | ein Gate mit `ABANDON` blockiert `merge.sh` (product-owner und merge-gate) und `done` mit `HANDOFF REQUIRED`, der PR bleibt offen, nichts wird geschrieben; `rft` und `gates.py run` ueberspringen das Gate; nach dem Entscheid des product-owner geht der Merge durch |
| `98` | Gate I/O errors | an unwritable ledger (`run`, `attest`) and a ledger that is not valid UTF-8 (`planned`, `lint`, `unmet`, `abandoned`, `qa-lines`) end in one error line naming the file, exit 1, no stack trace; `status.sh planned` rejects and writes nothing |
| `99` | Merge report | `planned` records every gate definition as `GATES Revision 1`; `merge.sh` prints each AC of the issue once with its ledger state and the diff's files, before any rejection; a failed read of comments, issue text or file list is `UNKNOWN`; a CHECK changed after planned and an AC without a gate are shown and do not block the merge; a ticket without a GATES line is reported as such |
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
