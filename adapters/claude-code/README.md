# Adapter: claude-code

Auf dieser Maschine verifiziert am 2026-09-09.

## 1. Session starten

Ein Terminal je Rolle, alle im selben Ordner:

```bash
cd "$KIT_WORKTREE_ROOT"
export KIT_ROLE=engineer-a
export KIT_HOST=claude-code
claude
```

## 2. Rollendatei laden

Erster Prompt an die Session, woertlich:

```
Lies roles/engineer.md und uebernimm die Rolle engineer-a.
```

Fuer Dauerbetrieb, damit die Rolle nicht auf Eingaben wartet:

```
/loop Arbeite deine Rolle laut roles/engineer.md weiter. Ein Ticket zur Zeit.
```

Der watchdog bekommt ein festes Intervall, weil seine Arbeit reines Messen ist:

```
/loop 5m Fuehre eine watchdog-Runde aus: budget.sh, drei Blicke, commit.sh.
```

## 3. Session-Kennung

Die Kennung steht im Pfad des Scratchpad-Verzeichnisses, das die Session im Systemprompt
genannt bekommt: das letzte Pfadsegment vor `/scratchpad`. Dieselbe Kennung ist der
Dateiname des Transkripts unter `~/.claude/projects/<projekt-slug>/<kennung>.jsonl`.

`session-id.sh` leitet sie aus der juengsten Transkriptdatei ab. Genauer ist es, sie
explizit zu setzen:

```bash
export KIT_SESSION_ID=<kennung aus dem Scratchpad-Pfad>
```

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
