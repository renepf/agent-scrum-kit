# LOOP — Betriebsprotokoll des Agenten-Teams

Host-unabhaengig. Wie eine Session **gestartet** wird, steht nicht hier, sondern in
`adapters/<host>/README.md`.

## 1. Grundsatz

Jede Rolle ist eine eigene Session in einem eigenen Terminal, mit eigenem Kontextfenster.
**Es werden keine Subagenten gespawnt.** Jede Session arbeitet im Haupt-Thread an genau
einem Ticket zur Zeit.

Zwei Wahrheiten, strikt getrennt:

| Was | Wo | Wer schreibt |
|---|---|---|
| **Ticketstatus** — wer ist dran, wo steht das Ticket | Issue: Status-Label + Assignee | die Rolle, die den Status besitzt |
| **Begruendung, Befund, Querverkehr** | `sprints/<sprint>/chat/<rolle>.md` | jede Rolle nur ihre eigene Datei |

Der Chat entscheidet **nie**, wer dran ist. Wer neu startet, liest Board und `INDEX.md` und
weiss alles. Faellt der Chat aus, laeuft der Loop weiter.

## 2. Statusmodell

Der Status haengt als Label am Issue. Praefix und Zustaende kommen aus `kit.env`
(`KIT_LABEL_PREFIX`, `KIT_STATES`).

| # | Status | Bedeutung | Owner | Weiter wenn |
|---|---|---|---|---|
| 1 | `open` | Ticket existiert, noch nicht geschnitten | **product-owner** | ACs stehen, Loesungsweg abgestimmt |
| 2 | `planned` | ACs fix, Verdict gesprochen, im Sprint | **product-owner** | ein Engineer nimmt es auf |
| 3 | `in-progress` | Implementierung laeuft | **engineer-a** / **engineer-b** (Assignee) | Arbeit fertig **und** PR offen |
| 4 | `rfr` | Ready for Review | **niemand** (Assignee leer) | ein Pruefer nimmt es auf |
| 5 | `in-review` | qa-ruthless, simplicity-reviewer, security-engineer pruefen | **die drei Pruefer** | alle drei Verdicts liegen vor |
| 6 | `rft` | Ready for Testing — Acceptance-Test am laufenden Bau | **acceptance-tester** + **product-owner** | Test bestanden, merge-gate gibt OK, CI gruen |
| 7 | geschlossen | Issue zu | **product-owner** | — |

`rfr` und `rft` sind bewusst besitzerlos beziehungsweise geteilt: sie sind das sichtbare
Zeichen, dass jetzt eine andere Rolle dran ist.

### Rueckwaertskante — die einzige

Findet ein Pruefer in `in-review` oder der Tester in `rft` einen Fehler, geht das Ticket
zurueck auf `in-progress`, Assignee wieder der urspruengliche Engineer. Danach laeuft
**dieselbe Schleife von vorn**: `in-progress → rfr → in-review → rft`. Es gibt keine
Abkuerzung und kein "kleiner Fix, direkt durchwinken".

```
open ──▶ planned ──▶ in-progress ──▶ rfr ──▶ in-review ──▶ rft ──▶ closed
                          ▲                      │            │
                          └──────────────────────┴────────────┘
                                   Fehler gefunden
```

Erlaubt sind genau diese Kanten:

```
open → planned
planned → in-progress
in-progress → rfr
rfr → in-review
in-review → rft
in-review → in-progress      (Rueckwaertskante)
rft → in-progress            (Rueckwaertskante)
rft → closed
```

Alles andere lehnt `bin/status.sh` ab. Ein Sprung von `planned` nach `rft` ist ein Fehler,
kein Sonderfall.

### Statuswechsel — der exakte Befehl

```bash
bin/status.sh <ticket> <neuer-status> "<einzeiler>"
```

Das Skript entfernt alle Status-Labels, setzt genau eines, passt den Assignee an und
schreibt einen Kommentar mit Rolle, Session-ID und Zeit. Kein Agent setzt Labels von Hand.

## 3. Cast — neun Sessions

| # | Rolle | Auftrag | Besitzt Status |
|---|---|---|---|
| 1 | `product-owner` | Sprint schneiden, ACs schreiben, Verdict einholen, mergen, schliessen | `open`, `planned`, `rft` (geteilt), Merge |
| 2 | `engineer-a` | Implementierung, TDD, PR | `in-progress` |
| 3 | `engineer-b` | dasselbe, zweite Instanz | `in-progress` |
| 4 | `qa-ruthless` | sucht, was nicht getestet ist; schreibt fehlende Tests | `in-review` |
| 5 | `simplicity-reviewer` | sucht unnoetige Komplexitaet; liefert eine Loeschliste | `in-review` |
| 6 | `security-engineer` | Eingaben, Deeplinks, Rechte, Krypto, Logs, Netz | `in-review` |
| 7 | `acceptance-tester` | prueft die ACs am laufenden Bau | `rft` (geteilt) |
| 8 | `merge-gate` | ganzheitlicher Review, CI, Freigabe — merged nie selbst | Gate vor Close |
| 9 | `watchdog` | Tokenstand messen, Stopp-Flags, Schlange, committen | — |

Dazu ausserhalb des Loops: `kit-maintainer` — schlaegt Aenderungen an Jobbeschreibungen
als Pull Request vor. Siehe `roles/kit-maintainer.md`.

**Merge-Hoheit liegt beim product-owner.** Er merged erst, wenn `merge-gate` sein OK
kommentiert hat **und** die CI gruen ist.

## 4. Sprint

Ein Sprint umfasst `KIT_SPRINT_TICKETS` Tickets im Takt von `KIT_TICKET_MINUTES` Minuten,
zwei Engineers parallel. Ueberzieht einer, startet sein naechstes Ticket am naechsten
Rasterpunkt — der Raster verschiebt sich nie.

```
sprints/S-<nnn>-<slug>/
├── sprint.md      # Ziel, die Ticketnummern, Start, Definition of Done
├── roster.md      # GENERIERT — Rolle, Session-ID, Startzeit
├── INDEX.md       # GENERIERT — alle Chat-Zeilen chronologisch, mit datei:zeile
├── budget.md      # GENERIERT — Kontextstand je Session (watchdog)
├── simqueue.md    # wer haelt gerade ein exklusives Geraet
└── chat/<rolle>.md
```

## 5. Chat — append-only, mit generiertem Index

Jede Rolle schreibt **nur** ihre eigene Datei unter `chat/` und haengt nur an. Bestehende
Zeilen werden **nie** editiert — die Zeilennummern im Index muessen fuer immer gueltig
bleiben.

```bash
bin/say.sh "#<ticket> · <betreff>" <<'EOF'
<rumpf>
EOF
```

`say.sh` haengt unter Sperre an, dann laeuft `reindex.sh`. `INDEX.md` wird **immer
vollstaendig neu gebaut**, nie fortgeschrieben, und atomar ersetzt: erst in eine temporaere
Datei schreiben, dann umbenennen. Ein halb geschriebener Index kann so nie gelesen werden,
und gleicher Input ergibt immer dieselbe Ausgabe.

Lesen kostet wenig: `tail -60 INDEX.md`, und nur bei einem Treffer per
`sed -n '212,240p' chat/<rolle>.md` in die Quelle springen.

## 6. Nur eine Rolle committet

Alle Sessions laufen auf derselben Maschine im selben Ordner und sehen einander sofort
ueber das Dateisystem. Git ist nur Historie. Neun parallele `git pull --rebase` sind die
einzige echte Konfliktquelle — deshalb committet ausschliesslich der `watchdog`, im Takt,
per `bin/commit.sh`.

## 7. Tokenbudget und Reset

Zwei Bremsen, unabhaengig voneinander:

1. **Watchdog, echte Zahl.** `bin/budget.sh` liest die Transkripte des Hosts und schreibt
   `budget.md`. Ab `KIT_WARN_TOKENS` nimmt die Rolle kein neues Ticket mehr an, ab
   `KIT_STOP_TOKENS` steht `STOP <rolle>` in `budget.md`.
2. **Notbremse, ohne Watchdog.** Nach `KIT_MAX_TICKETS` abgeschlossenen Tickets geht eine
   Rolle ohnehin in den Ruhestand. Diese Regel gilt auch, wenn der Watchdog ausgefallen ist
   oder der Host gar keine Transkripte schreibt.

**Kontextgroesse** heisst: der groesste Eingabestand eines **einzelnen** Turns
(`input_tokens` + `cache_read_input_tokens` + `cache_creation_input_tokens`).
Das ist die Zahl, die das Fenster fuellt — **nicht** die Summe ueber alle Turns.

Ablauf beim Reset, immer an einer Ticketgrenze, nie mitten im Ticket:

1. laufendes Ticket abschliessen oder den Status zurueckgeben
2. Uebergabe in die eigene Chat-Datei: Ticket, Stand, SHA, was als naechstes ansteht
3. Kontext leeren — **neue Session, nicht verdichten.** Verdichten verliert die
   technischen Details, an denen die naechste Runde haengt.
4. `bin/register.sh` erneut — neue Session-ID in `roster.md`
5. Rollenblatt neu laden, `tail -60 INDEX.md` lesen, weiterarbeiten

## 8. Geraete-Schlange

Exklusive Geraete (Emulator, Simulator, Testhardware) werden nie parallel benutzt. Wer eines
braucht, traegt sich in `simqueue.md` ein und wartet, bis er oben steht. Ein Eintrag mit
Status `HAELT`, aelter als 30 Minuten, wird vom Watchdog als verwaist entfernt.

## 9. Ueberleben

Naehert sich das Konto-Limit, pausieren **alle** Sessions. Keine neuen Dispatches. Der
Watchdog meldet das und gibt erst frei, wenn das Limit zurueckgesetzt ist. Das Limit wird
nicht gestreift.
