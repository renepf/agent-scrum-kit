# LOOP — Betriebsprotokoll des Agenten-Teams

Host-unabhaengig. Wie eine Session **startet**, steht in `adapters/<host>/README.md`.
Wie das Team eingerichtet wird, steht in `INSTALL.md`.

## 1. Grundsatz

Jede Rolle ist eine eigene Session in einem eigenen Terminal, mit eigenem Kontextfenster.
**Es werden keine Subagenten gespawnt.** Jede Session arbeitet im Haupt-Thread an genau einem
Ticket zur Zeit, und je Rolle laeuft genau **ein** Prozess.

Zwei Wahrheiten, strikt getrennt:

| Was | Wo | Wer schreibt |
|---|---|---|
| **Ticketstatus** — wo steht das Ticket | Status-Feld des GitHub Projects (`KIT_BOARD=github-project`), Label als Spiegel | nur `bin/status.sh` |
| **Besitz** — wer haelt es gerade | Label `owner:<rolle>` | nur `bin/status.sh` und `bin/claim.sh` |
| **Begruendung, Befund, Querverkehr** | `sprints/<sprint>/chat/<rolle>.md` | jede Rolle nur ihre eigene Datei |

Der Chat entscheidet **nie**, wer dran ist. Faellt der Chat aus, laeuft der Loop weiter.

Besitz haengt am Label, nicht am Assignee: alle Sessions teilen oft **einen** Account, und der
Assignee kann `engineer-a` und `engineer-b` nicht unterscheiden.

## 2. Statusmodell — acht Zustaende

| # | Schluessel | Board | Bedeutung | Besitz (`owner:`) | Weiter wenn |
|---|---|---|---|---|---|
| 1 | `backlog` | Backlog | Ticket existiert, noch nicht geschnitten | — (product-owner) | Story + ACs stehen, Loesungsweg abgestimmt |
| 2 | `planned` | Planned | im Sprint, bereit zur Aufnahme | **niemand** | ein Engineer nimmt auf |
| 3 | `in-progress` | In progress | Implementierung laeuft | genau **ein** Engineer | fertig **und** PR offen |
| 4 | `rfr` | RfR | Ready for Review — wartet | **niemand** | ein Pruefer nimmt auf |
| 5 | `in-review` | In review | Pruefer arbeiten **aktiv**, parallel | qa-ruthless, simplicity-reviewer, security-engineer | alle drei PASS fuer den aktuellen HEAD |
| 6 | `rft` | RfT | Ready for Testing — wartet | **niemand** | acceptance-tester nimmt auf |
| 7 | `in-testing` | In Testing | Acceptance-Test am laufenden Bau | acceptance-tester | ACCEPTANCE PASS, MERGE-GATE OK, PO-Entscheid |
| 8 | `done` | Done | gemergt und geschlossen, **kein** Label | — | — |

**Ready heisst wartend, In heisst aktiv.** Wer ein Ticket aufgreift, setzt **sofort** den
In-Status; ein weiterer Pruefer steigt mit `bin/claim.sh` ein.

### Erlaubte Kanten — genau diese

```
backlog → planned → in-progress → rfr → in-review → rft → in-testing → done
                        ▲                    │                    │
                        └────────────────────┴────────────────────┘
                                   Rueckwaertskante
```

| Kante | Wer darf | Pruefung vor dem Schreiben |
|---|---|---|
| `backlog → planned` | product-owner | **Ledger:** `tickets/<nr>/GATES.md` hat je `AC-<n>` des Issues ein Gate |
| `planned → in-progress` | engineer-a, engineer-b | setzt `owner:<engineer>` |
| `in-progress → rfr` | der Engineer mit `owner:` | fremder Besitz wird abgelehnt; **Umfang:** jede Datei des PR liegt in der freigegebenen OWNS-Revision |
| `rfr → in-review` | ein Pruefer | setzt `owner:<pruefer>`, weitere Pruefer bleiben |
| `in-review → rft` | ein Pruefer | **Gate:** QA PASS, SIMPLICITY PASS, SECURITY PASS fuer den aktuellen HEAD; jedes ausfuehrbare Gate des Ledgers lief fuer diesen HEAD gruen; Lint ohne Fehler; je ausfuehrbarem Gate eine QA-Mutationszeile |
| `rft → in-testing` | acceptance-tester | — |
| `in-testing → done` | product-owner, oder merge-gate mit `PO OK` fuer den aktuellen HEAD | normal ueber `bin/merge.sh`; jedes Gate fuer den aktuellen HEAD gruen oder belegt; kein offenes `ABANDON` |
| `in-review → in-progress` | ein Pruefer | `owner:` zurueck an den Engineer aus der Kommentarhistorie |
| `in-testing → in-progress` | acceptance-tester, merge-gate, product-owner | dasselbe |

Jeder andere Uebergang wird abgelehnt. Nach einer Rueckweisung laeuft **dieselbe Schleife von
vorn**: in-progress → rfr → in-review → rft → in-testing. Keine Abkuerzung, kein "kleiner Fix".

### Reihenfolge in `bin/status.sh`

1. **Alles pruefen, bevor irgendetwas geschrieben wird:** Kante, Rolle, Besitz, Gate. Eine
   abgelehnte Transition fasst weder Board noch Label noch Kommentar an.
2. **Board zuerst**, dann den Wert **zuruecklesen**. Weicht er ab oder scheitert der Aufruf,
   bricht das Skript ab, und das Label bleibt unveraendert.
3. Label als Spiegel, `owner:`-Besitz, Issue-Kommentar mit Rolle, Session-ID und Zeit, Chat.

### Verdicts gelten nur fuer einen HEAD

Ein Verdict ist ein PR-Kommentar, dessen erste Zeile mit `<VERDICT> — HEAD \`<sha8>\`` beginnt.
Ein Push entwertet alle Verdicts fuer den alten HEAD. `status.sh` und `merge.sh` pruefen das
maschinell.

### Gate-Ledger je Ticket

Vor `planned` hat jedes Ticket einen pruefbaren Vertrag unter `tickets/<nr>/GATES.md` (Ort:
`KIT_TICKETS_DIR`). Das Issue nennt jedes Acceptance-Kriterium als eigene Zeile
`AC-<n>: <beobachtbares ergebnis>`, das Ledger hat fuer jede dieser IDs ein Gate. Format und Regeln
stammen aus unlazy (MIT), die Einzelheiten stehen in `bin/gates.py`.

```
# Gates: #<nr> <titel>

OWNS: <pfade, die dieses Ticket aendern darf, z.B. src/export/**, tests/export/**>

- [ ] AC-1: <ergebnis>
  CHECK: <befehl, der das Ergebnis direkt misst>
  EXPECT: <text, den nur der Erfolg druckt>
  EVIDENCE: pending

- [ ] AC-2: <ergebnis, das nur ein Mensch am laufenden Bau sieht>
  EVIDENCE: pending
```

Jede `AC-<n>` im Issue-Text zaehlt, in jeder Schreibweise, ausser in Codebloecken und HTML-Kommentaren.

`planned` haelt `OWNS:` in seinem Issue-Kommentar als Zeile `OWNS Revision 1: \`<globs>\`` fest.
Diese Zeile ist die Freigabe. `rfr` liest nur Kommentare, deren erste Zeile der product-owner
geschrieben hat, und nimmt die hoechste Revision. Aendert jemand `OWNS:` im Ledger, erweitert das
nichts, bis der product-owner `bin/revise.sh <nr> "<globs>" "<grund>"` ausfuehrt: die Globs im Aufruf
muessen dem Ledger gleichen, der Kommentar nennt alten und neuen Umfang und den Grund.

OWNS-Globs: `**` ueber Verzeichnisgrenzen und nur als ganzes Segment, `*` und `?` innerhalb eines
Namens, `/` am Ende heisst alles darunter, ein Pfad ohne Glob ist genau eine Datei. Verboten sind
absolute Pfade, `..` und alles, was die ganze Wurzel freigibt (`**`, `*`, `./**`). Bei einer
Umbenennung zaehlt auch der alte Pfad.

Zwei Tickets desselben Sprints halten nie dieselbe Datei. Ein Pfad ohne Glob ist eine Datei: er
ueberschneidet sich mit einem Glob, der ihn trifft. Zwei Globs gelten nur dann als getrennt, wenn ein
woertliches Pfadsegment abweicht, bevor auf einer Seite ein Glob-Zeichen steht — `src/*.py` und
`src/*.kt` gelten also als ueberlappend. Im Zweifel lehnt das Kit ab. Ein Sprint-Ticket ohne Freigabe
haelt nichts.

`bin/gates.sh run <nr>` fuehrt im Arbeitsbaum des PR jedes ausfuehrbare Gate aus, nur wenn der
Arbeitsbaum auf dem HEAD des PR steht. Gruen heisst Exit 0 und `EXPECT` in stdout plus stderr; dann
steht `- [x]` und `EVIDENCE: v1 head=<sha8> def=<digest> …`, sonst `- [ ]` und `EVIDENCE: pending`.
Ein Beleg gilt nur fuer diesen HEAD und diese Definition aus `CHECK`, `EXPECT` und `CWD`: ein Push
oder eine geaenderte Zeile macht ihn ungueltig. Zeitgrenze je Gate: `KIT_GATE_TIMEOUT` Sekunden. Ein
manuelles Gate belegt der acceptance-tester oder der product-owner fuer den aktuellen HEAD:
`bin/gates.sh attest <nr> <gate> "<beleg>"`. `CHECK` ist Shell-Code aus dem Ledger und laeuft mit den
Rechten der Session, die ihn startet.

Ein AC, das sich nicht liefern laesst, faellt nie still weg. Wer es aufgibt, schreibt an Spalte 1
`ABANDON: AC-<n> <grund und uebergabe>` ins Ledger. Review und Lauf ueberspringen dieses Gate;
`merge.sh` und `status.sh <nr> done` lehnen mit `HANDOFF REQUIRED` ab, solange die Zeile steht. Das
letzte Wort hat der product-owner: er nimmt das AC per Folgeticket aus Issue und Ledger, oder er
schickt das Ticket zurueck.

`planned` also records the definition of every gate as `GATES Revision 1: \`AC-1=<digest>, …\``
next to `OWNS Revision 1`. Before any check, `merge.sh` prints a merge report: each AC of the issue
exactly once with its ledger state (green or attested for the HEAD, not green with the reason,
ABANDONED, no gate in the ledger), `definition changed since approval` where a digest differs, and
the files in the diff. A failed read shows as `UNKNOWN` in the report. The report is a measurement
for the product-owner, not a check: it rejects nothing.

Grenze: Die Rolle kommt wie ueberall im Kit aus `KIT_ROLE` oder dem Anker. Wer sich als
product-owner ausgibt, kann freigeben. Der Kommentar macht das in der Issue-Historie sichtbar,
verhindern kann das Kit es nicht.

| Pruefung | Wo | Lehnt ab, wenn |
|---|---|---|
| Artefaktkette | `status.sh <nr> planned` | `tickets/<nr>/intent.md`, `spec.md` oder `plan.md` fehlt oder ist leer. Der `requirements-engineer` schreibt intent und spec, den Plan mit dem product-owner |
| Deckung | `status.sh <nr> planned` | das Ledger fehlt oder ist formal kaputt, das Issue nennt keine AC, eine AC hat kein Gate, das Ledger nennt eine AC, die das Issue nicht kennt, das Ledger nennt kein oder ein unzulaessiges `OWNS:`, ein Gate ist schon abgehakt oder per `ABANDON` aufgegeben |
| Ueberlappung | `status.sh <nr> planned`, `bin/revise.sh`, `bin/sprint-new.sh` | ein OWNS-Glob kann dieselbe Datei meinen wie die Freigabe eines anderen offenen Sprint-Tickets; bei `sprint-new.sh` wie das Ledger eines anderen Tickets im Schnitt |
| Lint | `status.sh <nr> planned`, `status.sh <nr> rft` | ein Orakel kann nicht fallen: `CHECK` gibt festen Text aus, `EXPECT` ist ein Wort wie `ok` oder `fertig`, ein `EXPECT`-Regex sieht aus wie ein Pfad, `EXPECT` ist nur eine Zahl aus dem Issue. Hinweise lehnen nicht ab und stehen im planned-Kommentar: manuelles Gate, Zahl im Titel eines manuellen Gates, Taetigkeit statt Ergebnis, ueberwiegend manuelles Ledger |
| QA-Mutation je Gate | `status.sh <nr> rft` | fuer ein ausfuehrbares Gate steht in keinem `QA PASS` fuer den aktuellen HEAD eine Zeile `<gate>: Mutation <was> → rot` |
| Gruen fuer HEAD | `status.sh <nr> rft` | ein ausfuehrbares Gate hat keinen gruenen Beleg fuer den aktuellen HEAD, oder seine Definition hat sich seit dem Lauf geaendert |
| Weglassen sichtbar | `bin/merge.sh <nr>`, `status.sh <nr> done` | ein Gate steht auf `ABANDON` (`HANDOFF REQUIRED`) |
| Belegt vor Merge | `bin/merge.sh <nr>` | wie oben, dazu ein manuelles Gate ohne Beleg fuer den aktuellen HEAD |
| Umfang | `status.sh <nr> rfr` | kein oder mehr als ein verknuepfter PR, keine Freigabe am Issue, die Dateiliste ist leer oder nicht lesbar, eine Datei des PR liegt ausserhalb der hoechsten freigegebenen Revision |

### Letztes Wort: product-owner

Vor `done` stehen im PR, beide fuer den aktuellen HEAD: `MERGE-GATE OK` vom merge-gate, dann die
Entscheidung des product-owner. Er merged selbst per `bin/merge.sh`, oder schreibt `PO OK`, womit
merge-gate `bin/merge.sh` ausfuehren darf. `merge.sh` prueft die Freigaben, misst die CI **frisch**,
merged, prueft `MERGED` und setzt `done`.

## 3. Cast — zehn Sessions

| Rolle | Auftrag | Nimmt auf (`KIT_QUEUE_MAP`) |
|---|---|---|
| `product-owner` | Sprint, Stories, ACs, Takt, letztes Wort | alle |
| `requirements-engineer` | `intent.md` und `spec.md` je Ticket, `plan.md` mit dem product-owner | `backlog` |
| `engineer-a`, `engineer-b` | Implementierung, TDD, PR | `planned`, Rueckweisungen zuerst |
| `qa-ruthless` | fehlende Tests, Mutationen, Acceptance-Tests | `rfr`, `in-review` |
| `simplicity-reviewer` | Loeschliste, Verdict zum Loesungsweg vor `planned` | `rfr`, `in-review` |
| `security-engineer` | Eingaben, Rechte, Krypto, Logs, Netz | `rfr`, `in-review` |
| `acceptance-tester` | ACs am laufenden Bau | `rft` |
| `merge-gate` | ganzheitlicher Review, CI, Freigabe | `in-testing` |
| `watchdog` | Tokenstand, Zwillinge, Schlange, Commit | — |

Ausserhalb des Loops: `kit-maintainer` — Aenderungen an Jobbeschreibungen als Pull Request.

## 4. Loop-Reihenfolge

### Start

1. `product-owner` und `simplicity-reviewer` zuerst: der product-owner braucht vor `planned` das
   Verdict zum Loesungsweg, und erst `sprint-new.sh` legt `sprints/CURRENT` an.
2. `watchdog`, damit Budget und Zwillinge ab dem ersten Ticket gemessen werden.
3. Alle uebrigen sofort danach. Sie brauchen keinen Sonderfall: `tick.sh` meldet "kein aktiver
   Sprint" und endet mit Exit 0; sobald der Sprint steht, registriert es sie beim naechsten Tick.

### Jede Runde, jede Rolle

1. `bin/tick.sh` — Registrierung und Zwillingssperre, nach Reset `brain.sh recall`.
2. **Rueckweisungen zuerst** (Engineers).
3. Eigene Tickets (`owner:<rolle>`) fortsetzen, bevor ein freies aufgenommen wird.
4. Ein freies Ticket aus der eigenen Warteschlange aufnehmen — sofort den In-Status setzen.
5. Nichts davon: Runde beenden.

### Feste Intervalle

| Rolle | Intervall | Grund |
|---|---|---|
| `watchdog` | 5 min | reines Messen, muss STOP und Zwillinge rechtzeitig sehen |
| `engineer-a`, `engineer-b` | 5 min | `planned` und Rueckweisungen schnell aufgreifen |
| `qa-ruthless`, `simplicity-reviewer`, `security-engineer` | 5 min | `rfr` ist der haeufigste Wartezustand; das `rft`-Gate darf nicht der Engpass sein |
| `acceptance-tester` | 10 min | Geraeteschlange ist seriell, schnelleres Pollen bringt nichts |
| `merge-gate` | 10 min | wartet auf `in-testing` und gruene CI, beides dauert |
| `product-owner` | 10 min | haelt den Takt, sieht alle Zustaende |
| `requirements-engineer` | 10 min | arbeitet vor dem Sprint; ein Ticket im `backlog` wartet nicht auf Minuten |

Runden ueberlappen innerhalb einer Session nicht. Ein Tick kostet rund zwei API-Aufrufe; neun
Rollen im 5- bis 10-Minuten-Takt liegen weit unter 5 000 Aufrufen je Stunde.

## 4a. Kanban — Durchsatz statt Halde

Der Tick misst je Runde und zeigt es dem product-owner: geplant, in Arbeit, Pruefschlange (`rfr` und
`in-review`), Testschlange (`rft` und `in-testing`). Die Zahlen sind eine Messung, kein Tor — entscheiden
muss der product-owner.

| Regel | Wert | Warum |
|---|---|---|
| geplant mindestens | `KIT_MIN_PLANNED` (7) | ein Engineer ohne freies Ticket steht still |
| in Arbeit | so viele wie Engineers | mehr erzeugt Halde, weniger laesst Kapazitaet liegen |
| Planungsstopp | Pruef- oder Testschlange ueber `KIT_QUEUE_STOP` (2) | vorn nachlegen hilft hinten nicht |
| blockiertes Ticket | Grund melden, nicht blockiertes aufnehmen | Warten ist teurer als Wechseln |

`bin/sprint-new.sh` lehnt ein Ticket ohne vollstaendige Artefaktkette ab, `status.sh <nr> planned` ebenso.

## 5. Sprint

Ein Sprint umfasst `KIT_SPRINT_TICKETS` Tickets im Takt von `KIT_TICKET_MINUTES` Minuten, zwei
Engineers parallel. Ueberzieht einer, startet sein naechstes Ticket am naechsten Rasterpunkt.

```
sprints/S-<nnn>-<slug>/
├── sprint.md      # Ziel, Tickets, Start, Definition of Done
├── roster.md      # GENERIERT — Rolle, Session-ID, Host, Host-PID
├── INDEX.md       # GENERIERT — alle Chat-Zeilen chronologisch, mit datei:zeile
├── budget.md      # GENERIERT — Kontextstand je Session (watchdog)
├── simqueue.md    # wer haelt gerade ein exklusives Geraet
├── .lease-<rolle> # GENERIERT — Zwillingssperre: Session-ID, Host-PID, Zeit
└── chat/<rolle>.md
```

## 6. Chat — append-only, mit generiertem Index

Jede Rolle schreibt **nur** ihre eigene Datei und haengt nur an. Bestehende Zeilen werden **nie**
editiert — die Zeilennummern im Index muessen fuer immer gueltig bleiben. `bin/say.sh` haengt unter
Sperre an und baut `INDEX.md` **vollstaendig neu**, atomar (temporaer schreiben, dann umbenennen).

## 7. Nur eine Rolle committet

Alle Sessions laufen auf derselben Maschine im selben Ordner und sehen einander sofort. Git ist nur
Historie. Neun parallele `git pull --rebase` waeren die einzige echte Konfliktquelle — deshalb
committet ausschliesslich der `watchdog`, im Takt, per `bin/commit.sh`.

## 8. Zwillingssperre

Je Rolle laeuft genau ein Prozess. `register.sh` (vom Tick aufgerufen) schreibt
`.lease-<rolle>` mit Session-ID, Host-PID und Zeit. Lebt die eingetragene PID noch, ist die Sperre
juenger als `KIT_LEASE_MINUTES` und ist die eigene PID eine andere, bricht der Tick mit
"zweite Instanz" ab. Anlass: eine Session wurde zweimal fortgesetzt; zwei Prozesse derselben Rolle
arbeiteten parallel, und `owner:<rolle>` trennt Rollen, nicht Zwillinge.

Kann der Adapter die Host-PID nicht ermitteln, warnt die Sperre nur (`UNKNOWN`) und blockiert nicht.

"Lebt" heisst: unter der PID laeuft ein **Host**-Prozess (`adapters/<host>/host-alive.sh`), nicht nur
irgendein Prozess — PIDs werden neu vergeben. Jeder Tick raeumt Anker toter oder neu vergebener PIDs
weg. Eine Hintergrund-Session, die die Rolle nur geerbt hat, tickt nicht (`is-background.sh`).

Eine Rolle beendet ihren Loop **nie** selbst, auch nicht bei Warnung oder STOP, und stellt keine
Rueckfrage, die auf Eingabe wartet. Beides hat im Betrieb eines Referenz-Loops das ganze Team
angehalten (`evals/findings/2026-09-14-lehren-aus-dem-referenz-loop.md`).

## 9. Gedaechtnis

Der Chat ist das Gespraech eines Sprints. `memory/<rolle>/` ist das Gedaechtnis einer Rolle ueber
Sprints und Resets hinweg, `memory/_shared/` das Wissen aller. Werkzeug `bin/brain.sh`, Regeln
`memory/README.md`. Der Tick holt es nach jedem Reset automatisch zurueck.

## 10. Tokenbudget und Reset

1. **Watchdog, echte Zahl.** `bin/budget.sh` liest die Transkripte des Hosts. Ab `KIT_WARN_TOKENS`
   nimmt die Rolle kein neues Ticket an, ab `KIT_STOP_TOKENS` steht `STOP <rolle>` in `budget.md`.
2. **Notbremse, ohne Watchdog.** Nach `KIT_MAX_TICKETS` Tickets ohnehin Ruhestand — auch wenn der
   Watchdog ausfaellt oder der Host keine Transkripte schreibt.

**Kontextgroesse** ist der groesste Eingabestand eines **einzelnen** Turns
(`input_tokens` + `cache_read_input_tokens` + `cache_creation_input_tokens`), **nicht** die Summe.

Reset immer an einer Ticketgrenze: `brain.sh handover` → Kontext leeren (**nicht verdichten**).
Der Host-Prozess darf dabei weiterleben: die Rolle haengt am Anker `.pid-roles/<host-pid>`, nicht am
Kontext. Der naechste Tick erkennt die neue Session-ID, registriert sie und zeigt die Uebergabe.

Autonom geht das mit `bin/restart-self.sh`. Es beendet den Host-Prozess nur, wenn (1) eine Uebergabe
juenger als 10 Minuten existiert und (2) diese Uebergabe jedes Sprint-Ticket mit `owner:<rolle>` als
`#<nr>` nennt — mitten im Ticket zuruecksetzen ist damit erlaubt, die Uebergabe traegt dann Stand, SHA
und naechsten Schritt. Neu gestartet wird auf einem von zwei Wegen:

- **unter der Waechter-Schleife** (`adapters/<host>/role-loop.sh`): Prozess beenden, die Schleife startet neu;
- **in zellij ohne Schleife**: einen Tab `<rolle> (loop)` mit `role-loop.sh <rolle> --after <pid>` oeffnen und
  den Prozess erst beenden, wenn die Schleife nachweislich laeuft. Die Schleife wartet, bis unter der
  alten PID kein Host mehr lebt.

Gibt es keinen der beiden Wege, oder scheitert das Oeffnen des Tabs, beendet das Skript nichts.

## 11. Geraete-Schlange und Ueberleben

Exklusive Geraete werden nie parallel benutzt: Eintrag in `simqueue.md`, warten bis oben. Ein
`HAELT`-Eintrag aelter als 30 Minuten wird vom Watchdog entfernt.

Naehert sich das Konto-Limit, pausieren **alle** Sessions. Keine neuen Aufnahmen. Der Watchdog
meldet es und gibt erst frei, wenn das Limit zurueckgesetzt ist.
