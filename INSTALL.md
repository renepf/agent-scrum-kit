# Installation

Vom leeren Rechner bis zum ersten Tick. Jeder Befehl hier wurde am 2026-09-10 gegen
`renepf/agent-scrum-kit` und das Board `renepf/projects/5` ausgefuehrt, ausser er traegt den
Vermerk **ungeprueft**.

## 0. Voraussetzungen

| Werkzeug | Wozu | Pruefen |
|---|---|---|
| `bash`, `python3` | alle Skripte unter `bin/` und `evals/` | `bash --version`, `python3 --version` |
| `git` | Historie, nur der watchdog committet | `git --version` |
| `gh` (GitHub CLI), angemeldet | Tickets, PRs, Board | `gh api user -q .login` druckt deinen Login |
| ein Host aus `adapters/` | die Sessions selbst | `adapters/<host>/README.md` |

Der `gh`-Token braucht die Scopes `repo` und `project`; `read:org`, wenn das Board einer
Organisation gehoert. Pruefen und nachziehen:

```bash
gh auth status | grep -i scopes
gh auth refresh --scopes project          # nur, wenn 'project' fehlt — ungeprueft (Token hatte den Scope; nur --help gelesen)
```

**Zwei verschiedene Fehler, zwei verschiedene Loesungen.** `Requires authentication` oder HTTP 401
heisst: Token tot oder fehlt → neu anmelden. `missing required scopes` heisst: Token gueltig,
Berechtigung fehlt → nur den Scope nachziehen. `bin/preflight.sh` unterscheidet beides.

## 1. Kit ins Projekt legen

Das Kit bleibt ein **eigener Ordner mit eigener Historie** im Projekt. Nie seinen Inhalt ins Projekt
kopieren: es bringt eigene `README.md`, `AGENTS.md`, `CLAUDE.md`, `.gitignore` und `.git` mit. Der
watchdog committet Sprint-Stand und Gedaechtnis in die Historie des **Kits**, nie ins Projekt.

```bash
cd <dein-projekt>
git clone https://github.com/renepf/agent-scrum-kit.git
echo "agent-scrum-kit/" >> .gitignore      # ungeprueft: Standard-Git, nicht gemessen
cd agent-scrum-kit
```

Alle Sessions starten spaeter **in diesem Ordner**. Nur dort stimmen die Pfade `bin/…`, `roles/…`
und `sprints/…`. Die Engineers arbeiten trotzdem im Projekt, in Worktrees unter `KIT_WORKTREE_ROOT`.

Willst du die Historie des Kits nicht mitnehmen: `rm -rf .git && git init`, dann ein eigenes Remote
(**ungeprueft**, Standard-Git).

## 2. Konfiguration

```bash
cp kit.env.example kit.env
```

Pflicht in `kit.env`:

| Schluessel | Beispiel | Bedeutung |
|---|---|---|
| `KIT_REPO` | `meine-org/mein-projekt` | Repo mit Tickets und PRs |
| `KIT_WORKTREE_ROOT` | `$HOME/Developer/mein-projekt` | Arbeitsbaum des Projekts |
| `KIT_BASE_BRANCH` | `development` | Integrationsbranch |
| `KIT_HOST` | `claude-code` | Adapter unter `adapters/` |

Alles andere hat sinnvolle Werte. `kit.env` ist gitignored. Solange `KIT_REPO` auf `UNKNOWN` steht,
bricht jedes Skript ab.

```bash
bin/preflight.sh            # erwartet: preflight ok · gh · <login> · <repo>
```

## 3. Project-Board einrichten

Das Status-Feld des GitHub Projects ist die Wahrheit, das Label nur ein Spiegel.

**Ohne Board:** `KIT_BOARD="none"` lassen, nur `bin/board-setup.sh --labels-only` ausfuehren und
bei Schritt 4 weitermachen. Der Status lebt dann allein im Label.

### 3.1 Neues Board

```bash
gh project create --owner <login-oder-org> --title "<projektname> Scrum"
```

Die Ausgabe enthaelt die URL `…/projects/<nummer>`. In `kit.env`:

```bash
KIT_BOARD="github-project"
KIT_PROJECT_OWNER="<login-oder-org>"
KIT_PROJECT_NUMBER="<nummer>"
```

### 3.2 Status-Optionen, Verknuepfung, Labels

Ein neues Project hat als Status nur `Todo · In Progress · Done` (gemessen). `board-setup.sh`
ersetzt die Optionen durch die acht aus `KIT_STATUS_MAP`, verknuepft das Project mit `KIT_REPO` und
legt alle Labels an:

```bash
bin/board-setup.sh
```

Erwartete Ausgabe, gekuerzt:

```
Status-Optionen: Backlog → Planned → In progress → RfR → In review → RfT → In Testing → Done
verknuepft mit meine-org/mein-projekt
Label status:backlog
…
Label sprint:current
```

**Achtung:** Das Ersetzen der Optionen loescht den Status aller Tickets, die schon auf dem Board
liegen. Deshalb bricht das Skript ab, sobald das Board Eintraege hat.

### 3.3 Bestehendes Board mit Tickets

Nicht `--force`. Stattdessen:

1. Die Optionen des Status-Feldes im Board-UI so benennen und sortieren, wie `KIT_STATUS_MAP` es
   verlangt — oder die **Board-Namen** in `KIT_STATUS_MAP` an dein Board anpassen. Die Schluessel
   (`backlog`, `planned`, …) bleiben unveraendert, sie sind Protokoll.
2. Nur die Labels anlegen:

```bash
bin/board-setup.sh --labels-only
```

### 3.4 Pruefen, dass das Board das Statusmodell abbildet

```bash
bin/board-check.sh --write
```

Der Check prueft 23 Punkte: jede der acht Optionen mit exaktem Namen, keine ueberzaehlige Option,
die Reihenfolge, sieben `status:`-Labels, sechs `owner:`-Labels, das Sprint-Label. Nur wenn alle OK
sind, schreibt er die IDs nach `board.env` (generiert, gitignored). Gemessen am 2026-09-10:

```
OK    Board-Option Backlog               backlog → 6d109d41
…
OK    Reihenfolge                        board: Backlog → Planned → In progress → RfR → In review → RfT → In Testing → Done
…
board-check: alle Pruefpunkte OK — renepf/projects/5 bildet das Statusmodell ab.
board.env geschrieben: 10 IDs
```

| FAIL-Zeile | Bedeutung | Behebung |
|---|---|---|
| `Board-Option <Name> · fehlt` | der Loop kann diesen Status nicht setzen | Option im Board anlegen oder Namen in `KIT_STATUS_MAP` anpassen |
| `Board-Option <Name> · ueberzaehlig` | das Board zeigt einen Status, den der Loop nie setzt | Option entfernen (z.B. `Todo`) |
| `Reihenfolge` | Spalten folgen nicht der Vorwaertskante | Optionen im Board umsortieren |
| `Label <name> · fehlt im Repo` | `status.sh` kann Spiegel oder Besitz nicht setzen | `bin/board-setup.sh --labels-only` |

Aendert jemand spaeter die Optionen des Boards, aendern sich ihre IDs. Dann erneut
`bin/board-check.sh --write`.

## 3a. MCP-Server und Plugin

Das Kit liefert zwei MCP-Server fest aus und einen auf Einschalten. Jeder laeuft durch den Proxy
`caveman-shrink@0.1.0`, der die Tool-Beschreibungen kuerzt. Voraussetzung: `npx` (Node) und `uvx` (uv).

| Datei | Server | Standard |
|---|---|---|
| `.mcp.json` | context7, graphify | an |
| `adapters/claude-code/mcp/jcodemunch.json` | jcodemunch | **aus** — Lizenz nur nicht-kommerziell, siehe `adapters/claude-code/README.md` Abschnitt 5 |

Pruefen, dass jeder Server startet und antwortet (laedt die Pakete herunter):

```bash
evals/run.sh --net --case 93-mcp-handshake
```

graphify braucht einen Graphen unter `graphify-out/graph.json` im Kit-Ordner. Ohne ihn startet der
Server, findet aber nichts. Den Graphen des Projekts bauen:

```bash
uvx --from 'graphifyy[mcp]==0.9.57' graphify update "$KIT_WORKTREE_ROOT"   # ungeprueft mit diesem Pfad; gemessen nur 'graphify update .'
```

Das caveman-Plugin (Hooks und Skills, kein MCP) ist optional:

```bash
claude plugin marketplace add JuliusBrussee/caveman     # ungeprueft: nur --help gelesen
claude plugin install caveman@caveman                    # ungeprueft: nur --help gelesen
```

## 4. Evals

```bash
evals/run.sh                # statische Faelle, ohne Netz, ohne Modell
evals/run.sh --gh           # zusaetzlich: dein Board gegen das Statusmodell (liest nur)
evals/run.sh --live         # zusaetzlich: echte Modellaufrufe gegen claude-code (kostet Tokens)
evals/run.sh --net          # zusaetzlich: MCP-Handshakes, laedt npm- und PyPI-Pakete
```

Exitcode 0 = alles gruen, 1 = echter Fehlschlag, 2 = blockiert (Host oder GitHub nicht erreichbar,
Kontingent erschoepft — kein Urteil ueber das Kit).

## 5. Team starten

`roles/START-HERE.md`: Reihenfolge, Intervalle, Prompt. Der host-spezifische Befehl fuer den
Dauerbetrieb steht in `adapters/<host>/README.md`.

Jede Session startet mit Hook-Settings und MCP-Konfiguration:

```bash
cd <dein-projekt>/agent-scrum-kit
export KIT_ROLE=<rolle>
claude -n "$KIT_ROLE" --settings adapters/claude-code/settings.json --mcp-config .mcp.json
```

Beim **allerersten** Start in diesem Ordner fragt claude, ob du ihm vertraust. Die Vorauswahl ist
`No, exit` — waehle `Yes, I trust this folder`. Erst danach laufen die Hooks, und erst danach
startet eine Rolle unter `adapters/claude-code/role-loop.sh` ohne Menschen neu.

Einmal von Hand, bevor die Loops laufen:

```bash
export KIT_ROLE=product-owner
bin/tick.sh                 # erwartet: kein aktiver Sprint … Nichts zu tun.
```

## 6. Wenn etwas nicht laeuft

| Meldung | Ursache | Behebung |
|---|---|---|
| `kit.env fehlt` | Schritt 2 fehlt | `cp kit.env.example kit.env` |
| `KIT_ROLE ist nicht gesetzt` | Terminal ohne Rolle | `export KIT_ROLE=<rolle>` |
| `keine Session-ID` | Adapter kennt die Kennung nicht | `KIT_SESSION_ID` von Hand setzen, siehe Adapter |
| `zweite Instanz von '<rolle>'` | dieselbe Rolle laeuft schon in einem anderen Prozess | neue Session beenden, nicht die alte |
| `keine Board-Option fuer '<status>' in board.env` | Schritt 3.4 fehlt oder Board geaendert | `bin/board-check.sh --write` |
| `Board zeigt fuer #<nr> '…' statt '…'` | Board-Schreibzugriff nicht angekommen | erneut versuchen; das Label wurde bewusst nicht geaendert |
| `planned abgelehnt — kein Ledger` oder `AC ohne Gate` | das Ticket hat keinen pruefbaren Vertrag | je AC eine Zeile `AC-<n>:` im Issue, je AC ein Gate in `tickets/<nr>/GATES.md` |
| `rft abgelehnt — … fehlt fuer HEAD` | ein Verdict fehlt oder gilt einem alten HEAD | Verdict fuer den aktuellen HEAD im PR |
