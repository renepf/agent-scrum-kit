# agent-scrum-kit

Ein Agenten-Scrum-Team als Vorlage: neun Rollen, neun parallele Sessions, ein Ticket je
Session, **kein Subagent**. Kopierbar in jedes Projekt, lauffaehig auf mehreren LLM-Hosts.
Die Befehle unten gelten fuer den Host `claude-code`; fuer andere Hosts siehe
`adapters/<host>/README.md`.

## Kurzfassung

```bash
cd <dein-projekt> && git clone https://github.com/renepf/agent-scrum-kit && cd agent-scrum-kit
cp kit.env.example kit.env                  # 1. Repo, Pfade, Board eintragen
bin/board-setup.sh && bin/board-check.sh --write   # 2. Board + Labels einrichten, Abbildung pruefen
bin/preflight.sh && evals/run.sh --gh       # 3. alles muss gruen sein
export KIT_ROLE=product-owner && claude -n product-owner --settings adapters/claude-code/settings.json --mcp-config .mcp.json   # 4. je Terminal eine Rolle
# 5. erste Eingabe:  Lies roles/_COMMON.md und roles/product-owner.md und uebernimm die Rolle product-owner.
# 6. zweite Eingabe: /loop 10m Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite
#                    deine Rolle laut roles/product-owner.md. Kein Subagent.   (Intervall je Rolle: Tabelle 2.3)
```

Die ausfuehrliche Fassung folgt.

---

## 1. Einmalig einrichten

### 1.1 Kit ins Projekt legen und konfigurieren

Das Kit bleibt ein **eigener Ordner** im Projekt. Nie seinen Inhalt ins Projekt kopieren: das
Kit bringt eigene `README.md`, `AGENTS.md`, `CLAUDE.md`, `.gitignore` und `.git` mit und wuerde
die des Projekts ueberschreiben.

```bash
cd <dein-projekt>
git clone https://github.com/renepf/agent-scrum-kit
echo "agent-scrum-kit/" >> .gitignore      # das Kit hat seine eigene Historie
cd agent-scrum-kit
cp kit.env.example kit.env
```

In `kit.env` mindestens ausfuellen:

| Schluessel | Was hinein gehoert |
|---|---|
| `KIT_REPO` | das Repo mit den Tickets, `<org>/<repo>` |
| `KIT_WORKTREE_ROOT` | absoluter Pfad des Projekts, in dem die Engineers ihre Worktrees anlegen |
| `KIT_BASE_BRANCH` | der Integrationsbranch, auf dem niemand direkt arbeitet |
| `KIT_HOST` | `claude-code`, solange die anderen Adapter `UNKNOWN` tragen |

Alles andere hat einen Standardwert. `kit.env` ist gitignored.

### 1.2 Board und Labels einrichten

Mit Board ist das Status-Feld des GitHub Projects die Wahrheit und das Label nur ein Spiegel;
`bin/status.sh` schreibt beides, Board zuerst, und liest den Board-Wert zurueck. Die ausfuehrliche
Anleitung mit allen Sonderfaellen steht in `INSTALL.md`, Schritt 3.

```bash
gh project create --owner <login-oder-org> --title "<projekt> Scrum"   # URL enthaelt die Nummer
# in kit.env: KIT_BOARD="github-project", KIT_PROJECT_OWNER, KIT_PROJECT_NUMBER
bin/board-setup.sh           # 8 Status-Optionen, Verknuepfung mit KIT_REPO, alle Labels
bin/board-check.sh --write   # 23 Pruefpunkte; nur bei allen OK entsteht board.env
```

Ohne Board: `KIT_BOARD="none"` lassen und nur `bin/board-setup.sh --labels-only`.

### 1.3 Pruefen

```bash
bin/preflight.sh      # muss "preflight ok" drucken
evals/run.sh --gh     # muss "durchgefallen 0" drucken; --gh prueft dein echtes Board
```

Faellt `preflight.sh` mit `Requires authentication` durch, ist der Token tot: neu anmelden.
Nennt es `missing required scopes`, ist der Token gueltig und nur eine Berechtigung fehlt.

---

## 2. Team starten

### 2.1 Reihenfolge

1. **product-owner** und **simplicity-reviewer** zuerst. Der PO braucht vor `planned` das
   Verdict zum Loesungsweg, und erst sein `bin/sprint-new.sh` legt den Sprint an.
2. **watchdog** direkt danach. Er misst von Anfang an und ist die einzige Rolle, die committet.
3. Alle uebrigen in beliebiger Reihenfolge. Sie brauchen keinen Sonderfall: ihr Tick meldet
   "kein aktiver Sprint" und endet normal. Sobald der Sprint da ist, registriert sie der
   naechste Tick von selbst.

### 2.2 Jedes Terminal gleich

```bash
cd <dein-projekt>/agent-scrum-kit
export KIT_ROLE=<rolle>
claude
```

Die Session startet **im Kit-Ordner**. Nur dort stimmen die Pfade `bin/…`, `roles/…` und
`sprints/…` aus den Rollenblaettern. Claude Code laedt dann die `CLAUDE.md` des Kits, also den
Arbeitsvertrag, und die `CLAUDE.md` des Projekts eine Ebene darueber. Die Engineers arbeiten
trotzdem im Projekt: in Worktrees unter `KIT_WORKTREE_ROOT`.

`KIT_ROLE` muss **vor** dem Start von `claude` gesetzt sein. Eine laufende Session sieht eine
spaeter gesetzte Variable nicht.

Dann **zwei Eingaben**, nacheinander. Die erste liest die Rolle einmal ein:

```
Lies roles/_COMMON.md und roles/<datei> und uebernimm die Rolle <rolle>.
Fuehre dann bin/tick.sh aus und arbeite nach dem, was er dir zeigt.
Ein Ticket zur Zeit. Spawne niemals einen Subagenten.
```

Die zweite haelt die Rolle im Dauerbetrieb. Jede Runde beginnt mit dem Tick; die
Rollenblaetter werden **nicht** in jeder Runde neu gelesen, das wuerde Kontext verbrennen:

```
/loop <intervall> Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite deine Rolle laut roles/<datei>: ein Ticket zur Zeit, aufgreifen heisst sofort den In-Status setzen, kein Subagent.
```

Jede Rolle laeuft mit **festem Intervall** (Tabelle 2.3). Eine Runde ohne Arbeit endet nach dem
Tick; sie kostet einen Tick, nicht mehr.

### 2.3 Die neun Terminals

| # | `KIT_ROLE` | `<datei>` | `<intervall>` | wartet auf |
|---|---|---|---|---|
| 1 | `product-owner` | `product-owner.md` | `10m` | sieht alle Zustaende |
| 2 | `simplicity-reviewer` | `simplicity-reviewer.md` | `5m` | `@simplicity-reviewer` vom PO, dann `rfr` |
| 3 | `watchdog` | `watchdog.md` | `5m` | nichts, misst im Takt |
| 4 | `engineer-a` | `engineer.md` | `5m` | Rueckweisungen, dann `planned` |
| 5 | `engineer-b` | `engineer.md` | `5m` | Rueckweisungen, dann `planned` |
| 6 | `qa-ruthless` | `qa-ruthless.md` | `5m` | `rfr`, `in-review` |
| 7 | `security-engineer` | `security-engineer.md` | `5m` | `rfr`, `in-review` |
| 8 | `acceptance-tester` | `acceptance-tester.md` | `10m` | `rft` |
| 9 | `merge-gate` | `merge-gate.md` | `10m` | `in-testing` und `@merge-gate` |

Warum diese Takte: `protocols/LOOP.md` Abschnitt 4. `engineer-a` und `engineer-b` lesen dasselbe
Blatt; der Rollenname in der ersten Eingabe unterscheidet sie.

Der **watchdog** liest in seiner ersten Eingabe zusaetzlich die Budgetregeln:

```
Lies roles/_COMMON.md, roles/watchdog.md und protocols/LOOP.md Abschnitt 8 und 10
und uebernimm die Rolle watchdog. Du liest keinen Produktionscode und kommentierst keine
Issues. Fuehre bin/tick.sh aus, dann eine erste Runde bin/budget.sh.
Spawne niemals einen Subagenten.
```

```
/loop 5m Fuehre bin/tick.sh aus, dann eine watchdog-Runde laut roles/watchdog.md: budget.sh, vier Blicke, commit.sh.
```

Der **kit-maintainer** laeuft nicht mit. Du startest ihn nur, wenn in `evals/findings/` ein
Fall liegt oder `evals/run.sh` einen Fall als `FAIL` meldet — siehe `evals/README.md`.

### 2.4 Den ersten Sprint schneiden

Das macht der product-owner selbst, nach seinem Rollenblatt:

1. Stories in die Tickets schreiben — loesungsfrei, ELI5, eine Story je Ergebnis, je Kriterium
   eine Zeile `AC-<n>: <beobachtbares ergebnis>`.
2. Je Ticket das Ledger `tickets/<nr>/GATES.md`: je AC ein Gate (`protocols/LOOP.md`, Gate-Ledger).
3. `bin/sprint-new.sh <slug> <ticketnummern…>` — die Tickets bleiben dabei auf `backlog`.
   Erst dieser Schritt legt den Chat an; vorher scheitert jedes `say.sh` mit
   `kein aktiver Sprint`.
4. Den Loesungsweg per `@simplicity-reviewer` als Frage in den Chat stellen, Verdict abwarten.
5. Je Ticket `bin/status.sh <nr> planned "Verdict: <kurz>"`. Ohne Gate fuer jede AC lehnt es ab.

Am Ende jedes Tickets hat der product-owner das letzte Wort: `bin/merge.sh <nr>` merged erst,
wenn `MERGE-GATE OK` fuer den aktuellen HEAD im PR steht und die CI frisch gemessen gruen ist.

Ab hier brauchst du nichts mehr weiterzureichen. Ein Statuswechsel legt das Ticket in die
Warteschlange der naechsten Rolle; `@<rolle>` im Chat erreicht sie beim naechsten Tick.

---

## 3. Im Betrieb

### 3.1 Woran du siehst, dass es laeuft

```bash
S=sprints/$(cat sprints/CURRENT)
cat $S/roster.md          # wer ist registriert, mit welcher Session-ID
tail -20 $S/INDEX.md      # was zuletzt im Chat stand, mit datei:zeile
cat $S/budget.md          # Kontextstand je Rolle, etwaige STOP-Zeilen
KIT_ROLE=product-owner bin/tick.sh   # das Lagebild des PO, ohne eine Session zu stoeren
```

Fehlt eine Rolle in `roster.md`, tickt sie nicht. Meldet der watchdog eine Rolle als still
seit 45 Minuten, haengt ihre Session.

### 3.2 Wenn eine Session an ihrem Limit ist

`budget.md` traegt `STOP <rolle>`, und der Tick dieser Rolle zeigt es ihr. An der naechsten
Ticketgrenze schreibt sie ihre Uebergabe per `bin/brain.sh handover` und eine Zeile per `bin/say.sh`.
Danach gibt es zwei Wege; beide sind gemessen (2026-09-14, saubere Umgebung):

**`/clear` in der laufenden Session.** Der Prozess bleibt, die Session-ID wechselt. Der
SessionStart-Hook weckt die Session ohne Eingabe; sie liest ihr Rollenblatt, `bin/tick.sh`
registriert die neue ID und zeigt die Uebergabe, und der `/loop` laeuft weiter (die Session fand ihn
per `CronList` und legte keinen zweiten an). Die Rolle kommt aus dem Anker `.pid-roles/<pid>`, die
neue Session-ID aus `~/.claude/sessions/<pid>.json`. **Nicht `/compact`** — Verdichten verliert die
technischen Details, an denen die naechste Runde haengt.

**Ohne Menschen, per `bin/restart-self.sh stop`.** Die Rolle schreibt ihre Uebergabe (juenger als 10 min);
haelt sie noch Tickets, nennt die Uebergabe jedes `#<nr>` mit Stand, SHA und naechstem Schritt — ein
Neustart mitten im Ticket ist erlaubt (Fall 67). Laeuft sie unter `adapters/claude-code/role-loop.sh`,
beendet sie sich und die Schleife startet `claude` frisch. Laeuft sie ohne Schleife in zellij, oeffnet
das Skript einen Tab `<rolle> (loop)` mit `role-loop.sh <rolle> --after <pid>` und beendet sich erst,
wenn die Schleife laeuft; die wartet auf das Ende der alten Session (Fall 59, mit vorgetaeuschtem zellij
gemessen, nicht in einem echten zellij). Gemessen mit echtem `claude` (Fall 77, 2026-09-14): die Rolle schrieb ihre Uebergabe
und rief `restart-self.sh stop`, der alte Prozess endete nach 62 s (`rc=143`), die Schleife startete
`claude` neu, und 18 s spaeter stand die Rolle mit neuer PID und neuer Session-ID im Roster — ohne
Eingabe. Der Vertrauensdialog erscheint nur beim allerersten Start im Ordner, nicht beim Neustart.

Unabhaengig vom watchdog geht jede Rolle nach `KIT_MAX_TICKETS` Tickets ohnehin so in den Ruhestand.

### 3.3 Wenn der Tick "zweite Instanz" meldet

Dieselbe Rolle laeuft schon in einem anderen Prozess — typisch nach einem zweiten `--resume`
derselben Session. Die **neue** Session beenden, nicht die alte. Die Sperre gibt die Rolle frei,
sobald der alte Prozess beendet ist oder `KIT_LEASE_MINUTES` lang nicht getickt hat.

### 3.4 Wenn sich ein Rollenblatt oder ein Skript aendert

Skripte unter `bin/` wirken sofort beim naechsten Aufruf — alle Sessions teilen ein
Dateisystem. Ein **Rollenblatt** dagegen hat jede laufende Session noch in der alten Fassung
im Kontext. Schick der betroffenen Session eine Zeile, bevor sie weiterarbeitet:

```
roles/<datei> hat sich geaendert. Lies <abschnitt> neu, bevor du dein naechstes Ticket
aufnimmst. Danach weiter wie bisher: bin/tick.sh in jeder Runde.
```

Aendert sich `roles/_COMMON.md`, betrifft das alle neun Sessions.

---

## Was wo liegt

| Ort | Inhalt |
|---|---|
| `AGENTS.md` | der Arbeitsvertrag. `CLAUDE.md` und `.cursorrules` verweisen darauf |
| `roles/` | neun Jobbeschreibungen plus `kit-maintainer`, reines Markdown, ohne Host-Vokabular |
| `INSTALL.md` | Einrichtung Schritt fuer Schritt, mit gemessenen Ausgaben und Fehlertabelle |
| `protocols/LOOP.md` | Statusmodell, Kanten, Gates, Loop-Reihenfolge, Tick, Chat, Zwillingssperre, Budget |
| `adapters/<host>/` | wie eine Session startet, eine Rolle laedt, ihre Kennung meldet |
| `bin/` | `tick.sh`, `status.sh`, `claim.sh`, `merge.sh`, `say.sh`, `reindex.sh`, `brain.sh`, `budget.sh`, `register.sh`, `restart-self.sh`, `sprint-new.sh`, `commit.sh`, `board-setup.sh`, `board-check.sh`, `preflight.sh`, `tickets.sh`, `gates.py`, `revise.sh` |
| `tickets/<nr>/` | `GATES.md`: Gate-Ledger je Ticket, je AC ein Gate, `OWNS:` als Umfang, Format und Regeln aus unlazy (MIT); die Freigabe des Umfangs steht als Kommentar am Issue |
| `evals/` | die Suite, die prueft, ob das alles haelt |
| `memory/` | Gedaechtnis je Rolle plus geteilt, eine Datei je Fakt, generierter Index |
| `.mcp.json` | MCP-Server context7 und graphify, beide durch `caveman-shrink`; jcodemunch auf Einschalten unter `adapters/claude-code/mcp/` |
| `kit.env` | **alles Projektwissen.** Kein Skript kennt dein Projekt, nur diese Datei |

## Die drei Regeln, die alles tragen

1. **Kein Subagent.** Eine Rolle ist eine Session im Haupt-Thread. Nebenlaeufigkeit entsteht
   durch parallele Sessions, nie innerhalb einer.
2. **Der Index ist generiert.** Chatdateien sind append-only, damit Zeilenverweise dauerhaft
   gelten. `INDEX.md` wird immer neu gebaut und atomar ersetzt.
3. **Nur eine Rolle committet.** Alle Sessions teilen ein Dateisystem und sehen einander
   sofort; Git ist nur Historie. Neun parallele Rebases waeren die einzige echte
   Konfliktquelle.

## Host-Unterstuetzung

| Host | Zustand |
|---|---|
| `claude-code` | vollstaendig, Live-Evals laufen dagegen |
| `cursor` | Start belegt, Sessionkennung und Transkripte `UNKNOWN` |
| `codex` | Startbefehl `UNKNOWN` — nicht geprueft |
| `pi` (PI Code, QWEN-Harness) | `UNKNOWN — beim Owner erfragen` |
| `hermes` | `UNKNOWN — beim Owner erfragen` |

Fehlt einem Adapter eine Angabe, steht dort `UNKNOWN`. Ein erfundener Startbefehl waere der
schlimmste Fehler, den dieses Repo machen kann.

## Lizenz

MIT, siehe `LICENSE`.
