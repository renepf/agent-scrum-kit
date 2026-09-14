# Adapter: claude-code

Auf dieser Maschine verifiziert am 2026-09-09.

## 1. Session starten

Ein Terminal je Rolle, alle im selben Ordner:

```bash
cd "$KIT_WORKTREE_ROOT"
export KIT_ROLE=engineer-a
claude
```

## 2. Rollendatei laden und Dauerbetrieb

Erster Prompt, woertlich, mit Intervall und Datei aus `roles/START-HERE.md`:

```
/loop 5m Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite deine
Rolle laut roles/engineer.md: ein Ticket zur Zeit, aufgreifen heisst sofort den In-Status setzen,
kein Subagent.
```

`/loop` mit festem Intervall startet die Runde auch dann, wenn die Rolle gerade auf nichts wartet.
Eine leere Runde endet nach dem Tick.

## 3. Session-Kennung, Host-PID, Kontext-Reset

- **Host-PID:** `host-pid.sh` geht die Prozesskette hoch bis zum Prozess `claude`. Die PID bleibt ueber
  alle Werkzeugaufrufe einer Session gleich — **und ueber `/clear` hinweg**.
- **Session-Kennung:** `session-id.sh` liest zuerst `~/.claude/sessions/<host-pid>.json` (Feld
  `sessionId`), dann `CLAUDE_CODE_SESSION_ID`. Gemessen 2026-09-14 in sauberer Umgebung: nach `/clear`
  traegt die Registry die neue ID bei gleicher PID. Ob `CLAUDE_CODE_SESSION_ID` ebenfalls wechselt, ist
  in sauberer Umgebung **nicht gemessen**. Nie aus der juengsten Transkriptdatei ableiten.
- **Lebender Host:** `host-alive.sh <pid>` prueft den Prozessnamen `claude`. Eine PID wird nach dem
  Ende neu vergeben; ein Anker darf dann nicht als laufende Rolle gelten. `bin/tick.sh` raeumt Anker
  toter oder neu vergebener PIDs bei jedem Tick weg.
- **Hintergrund-Sessions:** `is-background.sh` erkennt `CLAUDE_CODE_SESSION_KIND=bg`. Solche Sessions
  erben `KIT_ROLE`, sind aber keine Rolle. **Nicht** `CLAUDE_CODE_CHILD_SESSION` pruefen: die Variable
  steht in der Werkzeug-Umgebung jeder Session (Referenz-Messung 2026-09-14).
- **Rolle ueber `/clear`:** `bin/tick.sh` schreibt bei jedem Tick `.pid-roles/<host-pid>`. Ohne
  `KIT_ROLE` liest `bin/common.sh` die Rolle dort.
- **Start-Hook:** `settings.json` haengt `session-start.sh` zweimal an `SessionStart`: einmal fuer den
  Rollenanker als Kontext, einmal mit `--wake` (asyncRewake), das die Session nach `startup`, `clear`
  und `resume` ohne Eingabe weckt. Gemessen: Start ohne Prompt registriert sich; nach `/clear` liest
  die Session ihre Rolle neu, tickt (neue ID im Roster) und findet ihren laufenden `/loop`.
- **Waechter-Schleife:** `role-loop.sh <rolle>` startet `claude -n <rolle> --settings … --mcp-config
  .mcp.json` und startet neu, sobald es endet. Stoppen: `touch .role-loop/<rolle>.stop`. Gemessen mit
  vorgetaeuschtem `claude` (Fall 68: Neustart, Stopp, Aufgeben, Zwilling) und mit echtem `claude`
  (Fall 77: Selbst-Neustart per `restart-self.sh`, neue PID und Session-ID ohne Eingabe). Das
  Vertrauen in den Ordner speichert claude in `~/.claude.json` (`hasTrustDialogAccepted`), deshalb
  haengt der Neustart nicht am Dialog.
- **Absturzschutz beachten:** endet `claude` dreimal in Folge nach weniger als 60 s, gibt die Schleife
  auf. Eine Rolle, die sich direkt nach dem Wecken erneut zuruecksetzt, zaehlt dabei als schneller
  Abbruch.

**Messfalle fuer Tests:** Wer `claude` aus einer laufenden claude-Session heraus startet, vererbt
`CLAUDE_CODE_CHILD_SESSION=1`, `CLAUDE_PID` und den Messaging-Socket. Die gestartete Session schrieb
dann weder Registry noch Transkript am ueblichen Ort. Testsessions deshalb mit `env -i` und nur
`HOME PATH USER LANG TERM KIT_ROLE` starten (so in Fall 75 und 76).

## 4. Empfohlene Einstellungen fuer Opus 5

Quelle: NotebookLM-Sammlung des Owners ("Claude Best Principles", abgefragt 2026-09-09).
**Von mir nicht nachgemessen** — die Namen der Umgebungsvariablen in Punkt 3 unten habe ich
nicht gegen die Claude-Code-Dokumentation geprueft.

1. **Modell explizit setzen**, nie auf Standardwerte verlassen: `claude-opus-5`.
2. **Thinking nicht abschalten.** Abschalten fuehrt zu fehlerhaften Werkzeugaufrufen und
   sichtbaren internen Tags. Steuere Kosten stattdessen ueber den Effort-Grad:
   `medium` ist der Arbeitsbereich, `low` fuer Routine, `high` erzeugt Overthinking und
   Kursabweichung.
3. **Subagenten maschinell sperren** — die eiserne Regel steht sonst nur im Text:
   ```bash
   export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=0
   export CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=0
   ```
   `UNKNOWN — Namen gegen die Claude-Code-Dokumentation pruefen, Beleg bisher nur die
   NotebookLM-Quelle.` Die Eval `no-subagent` prueft das Verhalten, nicht die Variable.
4. **Kein `/compact`.** Verdichten verliert den Grossteil der technischen Details. Bei vollem
   Kontext: Uebergabe schreiben, Kontext leeren, neu starten. So steht es in
   `protocols/LOOP.md` Abschnitt 7.
5. **Keine "pruefe deine Antwort nochmal"-Anweisungen** in Prompts. Opus 5 verifiziert
   selbst; zusaetzliche Aufforderungen erzeugen Over-Verification und kosten Token ohne
   Gegenwert. Deshalb verlangt `AGENTS.md` eine **Messung**, keine Nachpruefschleife.
6. **Regeldateien schlank halten.** Ueber 300 Zeilen verschlechtern das Ergebnis messbar.
   `AGENTS.md` bleibt bewusst darunter, Details liegen in Unterordnern mit Routing-Tabelle.

## 4a. Dialoge, die einen unbeaufsichtigten Start blockieren

Gemessen am 2026-09-14 an einer interaktiven Session in einem frischen Kit-Ordner:

- **Vertrauensdialog beim ersten Start in einem Ordner.** Die Vorauswahl ist `❯ No, exit` — ein
  blindes Enter beendet claude. Einmal von Hand `Yes, I trust this folder` waehlen, bevor Rollen
  unter `role-loop.sh` laufen; sonst haengt jeder Neustart an diesem Dialog. Mit `-p` erscheint er
  nicht.
- **`/exit` mit laufendem `/loop`.** claude fragt `Background work is running … 1. Exit and stop
  tasks / 2. Stay`. Wer eine Rolle von Hand beendet, bestaetigt mit `1`. `bin/restart-self.sh`
  betrifft das nicht: es beendet den Prozess per `kill -TERM`.
- **Start ohne Eingabe.** Mit `--settings adapters/claude-code/settings.json` weckt der Hook
  `session-start.sh --wake` (asyncRewake) die Session nach dem Vertrauensdialog von selbst: sie las
  `roles/_COMMON.md` und `roles/engineer.md`, fuehrte `bin/tick.sh` aus, registrierte sich und legte
  ihren 5-Minuten-Loop per `CronCreate` an — ohne einen einzigen eingegebenen Prompt.
- In `-p` meldet derselbe Weck-Hook `outcome: error` (exit 2, Ankertext auf stderr). Die Session
  laeuft trotzdem normal durch; der Kontext-Hook liefert den Anker dort als `additionalContext`.

## 5. MCP-Server

Das Kit liefert MCP-Server in zwei Dateien aus. Jeder laeuft durch `caveman-shrink@0.1.0` (MIT), einen
stdio-Proxy aus dem caveman-Projekt, der die Tool-Beschreibungen kuerzt. Alle Versionen sind exakt
gepinnt; gemessen am 2026-09-14 per `initialize` + `tools/list`:

| Server | Datei | Paket | Lizenz | Tools | Beschreibungen roh → gekuerzt |
|---|---|---|---|---|---|
| context7 | `.mcp.json` | `@upstash/context7-mcp@4.1.0` (npx) | MIT | 2 | 2435 → 2351 Zeichen |
| graphify | `.mcp.json` | `graphifyy[mcp]==0.9.57` (uvx) | Apache-2.0 | 10 | 1229 → 1187 Zeichen |
| jcodemunch | `adapters/claude-code/mcp/jcodemunch.json` | `jcodemunch-mcp==1.108.318` (uvx) | Dual-Use, siehe unten | 6 | — |

Voraussetzungen: `npx` (Node) und `uvx` (uv). graphify liest `graphify-out/graph.json` relativ zum
Kit-Ordner; ohne Graph startet der Server trotzdem (gemessen). Den Graph baut `graphify update <pfad>`.

`graphifyy` braucht das Extra `[mcp]`: ohne es endet `graphify-mcp` mit
`ModuleNotFoundError: No module named 'mcp'` (gemessen an einer `uv tool install graphifyy`).

Start mit MCP:

```bash
claude -n "$KIT_ROLE" --settings adapters/claude-code/settings.json --mcp-config .mcp.json
```

### jcodemunch — nur auf Einschalten

`jcodemunch-mcp` steht unter der **jCodeMunch-MCP Dual-Use License 1.1**, nicht unter einer
Open-Source-Lizenz. Klausel 3: die Software darf nicht "in any product, service, or workflow that
generates revenue, is offered commercially, or is used within a for-profit organization to support
revenue-generating activities" genutzt werden. Kostenlos ist nur nicht-kommerzielle Nutzung;
kommerziell braucht es die Erlaubnis des Autors (J. Gravelle,
https://github.com/jgravelle/jcodemunch-mcp). Das Kit verteilt keinen Code, nur einen Startbefehl —
ob deine Nutzung erlaubt ist, musst du selbst pruefen. Deshalb ist es nicht in `.mcp.json`.

Einschalten:

```bash
claude … --mcp-config .mcp.json adapters/claude-code/mcp/jcodemunch.json
```

Die vom Server gemeldete Version ist unzuverlaessig (`==1.27.0` meldet sich als 1.30.0 mit 50 Tools);
gepinnt ist 1.108.318, eine Router-Fassung mit 6 Tools und rund 2400 Zeichen Beschreibung.

### caveman als Plugin

`caveman` selbst ist kein MCP-Server, sondern ein Plugin aus Hooks und Skills. Die Befehle unten
entsprechen `claude plugin marketplace add --help` und `claude plugin install --help`; ausgefuehrt
wurden sie auf der Messmaschine nicht, dort war das Plugin schon installiert (**ungeprueft**):

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```
