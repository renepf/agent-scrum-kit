# agent-scrum-kit

Ein Agenten-Scrum-Team als Vorlage: neun Rollen, neun parallele Sessions, ein Ticket je
Session, **kein Subagent**. Kopierbar in jedes Projekt, lauffaehig auf mehreren LLM-Hosts.
Die Befehle unten gelten fuer den Host `claude-code`; fuer andere Hosts siehe
`adapters/<host>/README.md`.

## Kurzfassung

```bash
cd <dein-projekt> && git clone https://github.com/renepf/agent-scrum-kit && cd agent-scrum-kit
cp kit.env.example kit.env                  # 1. Repo, Pfade, Schwellen eintragen
bin/preflight.sh && evals/run.sh            # 2. beides muss gruen sein
export KIT_ROLE=product-owner && claude     # 3. je Terminal eine Rolle, im Kit-Ordner, erst PO und simplicity-reviewer
# 4. erste Eingabe:  Lies roles/_COMMON.md und roles/product-owner.md und uebernimm die Rolle product-owner.
#                    Fuehre dann bin/tick.sh aus und arbeite nach dem, was er dir zeigt.
# 5. zweite Eingabe: /loop Fuehre bin/tick.sh aus und arbeite danach deine Rolle laut roles/product-owner.md weiter. Kein Subagent.
# 6. der PO schneidet den Sprint; alle anderen Rollen ticken sich von selbst hinein
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

### 1.2 Labels im Ticket-Repo anlegen

`bin/status.sh` setzt Labels, die im Repo existieren muessen:

```bash
source kit.env
for s in backlog planned in-progress rfr in-review rft in-testing; do
  gh label create "status:$s" --repo "$KIT_REPO"
done
gh label create "sprint:current" --repo "$KIT_REPO"
```

### 1.3 Projekt-Board anbinden (optional)

Ohne Board sind die Labels die Wahrheit. Mit Board ist das Board die Wahrheit und das Label
nur ein Spiegel; `bin/status.sh` schreibt beides zusammen. Die IDs holst du so:

```bash
gh project list --owner <org>
gh project field-list <projektnummer> --owner <org> --format json
```

Dann in `kit.env`: `KIT_PROJECT_ID`, `KIT_STATUS_FIELD_ID` und `KIT_STATUS_OPTIONS` im Format
`"backlog=<id> planned=<id> … done=<id>"`. Das Status-Feld des Boards braucht dafuer genau
diese acht Optionen.

### 1.4 Pruefen

```bash
bin/preflight.sh      # muss "preflight ok" drucken
evals/run.sh          # muss "durchgefallen 0" drucken
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
/loop Fuehre bin/tick.sh aus und arbeite danach deine Rolle laut roles/<datei> weiter. Ein Ticket zur Zeit. Kein Subagent.
```

### 2.3 Die neun Terminals

| # | `KIT_ROLE` | `<datei>` | Loop | wartet auf |
|---|---|---|---|---|
| 1 | `product-owner` | `product-owner.md` | ohne Intervall | sieht alle Zustaende |
| 2 | `simplicity-reviewer` | `simplicity-reviewer.md` | ohne Intervall | `@simplicity-reviewer` vom PO, dann `rfr` |
| 3 | `watchdog` | `watchdog.md` | **`/loop 5m`**, siehe unten | nichts, misst im Takt |
| 4 | `engineer-a` | `engineer.md` | ohne Intervall | `planned` |
| 5 | `engineer-b` | `engineer.md` | ohne Intervall | `planned` |
| 6 | `qa-ruthless` | `qa-ruthless.md` | ohne Intervall | `rfr` |
| 7 | `security-engineer` | `security-engineer.md` | ohne Intervall | `rfr` |
| 8 | `acceptance-tester` | `acceptance-tester.md` | ohne Intervall | `rft` |
| 9 | `merge-gate` | `merge-gate.md` | ohne Intervall | `in-testing` und `@merge-gate` |

`engineer-a` und `engineer-b` lesen dasselbe Blatt; der Rollenname in der ersten Eingabe
unterscheidet sie.

Der **watchdog** ist die einzige Rolle mit festem Intervall, weil seine Arbeit reines Messen
ist. Seine erste Eingabe liest zusaetzlich die Budgetregeln:

```
Lies roles/_COMMON.md, roles/watchdog.md und protocols/LOOP.md Abschnitt 7 und 8
und uebernimm die Rolle watchdog. Du liest keinen Produktionscode und kommentierst keine
Issues. Fuehre bin/tick.sh aus, dann eine erste Runde bin/budget.sh.
Spawne niemals einen Subagenten.
```

```
/loop 5m Fuehre bin/tick.sh aus, dann eine watchdog-Runde laut roles/watchdog.md: budget.sh, die Blicke, commit.sh.
```

Der **kit-maintainer** laeuft nicht mit. Du startest ihn nur, wenn in `evals/findings/` ein
Fall liegt oder `evals/run.sh` einen Fall als `FAIL` meldet — siehe `evals/README.md`.

### 2.4 Den ersten Sprint schneiden

Das macht der product-owner selbst, nach seinem Rollenblatt:

1. Stories in die Tickets schreiben — loesungsfrei, ELI5, eine Story je Ergebnis.
2. `bin/sprint-new.sh <slug> <ticketnummern…>` — die Tickets bleiben dabei auf `backlog`.
   Erst dieser Schritt legt den Chat an; vorher scheitert jedes `say.sh` mit
   `kein aktiver Sprint`.
3. Den Loesungsweg per `@simplicity-reviewer` als Frage in den Chat stellen, Verdict abwarten.
4. Je Ticket `bin/status.sh <nr> planned "Verdict: <kurz>"`.

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
Ticketgrenze schreibt sie ihre Uebergabe per `bin/say.sh`. Dann:

1. Session beenden (`/exit`) — **nicht** `/compact`. Verdichten verliert die technischen
   Details, an denen die naechste Runde haengt. Auch nicht `/clear`: die Session-Kennung kommt
   aus `CLAUDE_CODE_SESSION_ID`, und ob dieser Wert nach `/clear` wechselt, ist nicht geprueft.
   Ein neuer Prozess hat sicher eine neue Kennung.
2. Im selben Terminal `claude` neu starten. `KIT_ROLE` ist dort noch gesetzt.
3. Dieselben zwei Eingaben wie beim ersten Start. Der Tick registriert die neue Session-ID
   von selbst; der watchdog findet sie wieder.

Unabhaengig vom watchdog geht jede Rolle nach `KIT_MAX_TICKETS` Tickets ohnehin so in den
Ruhestand.

### 3.3 Wenn sich ein Rollenblatt oder ein Skript aendert

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
| `protocols/LOOP.md` | Statusmodell, Rueckwaertskante, Tick, Chat, Budget, Reset |
| `adapters/<host>/` | wie eine Session startet, eine Rolle laedt, ihre Kennung meldet |
| `bin/` | `tick.sh`, `status.sh`, `say.sh`, `reindex.sh`, `budget.sh`, `sprint-new.sh`, `commit.sh` |
| `evals/` | die Suite, die prueft, ob das alles haelt |
| `memory/` | dateibasiertes Langzeitgedaechtnis, eine Datei je Fakt |
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
