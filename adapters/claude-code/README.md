# Adapter: claude-code

Auf dieser Maschine verifiziert am 2026-09-09.

## 1. Session starten

Ein Terminal je Rolle, alle im selben Ordner:

```bash
cd <dein-projekt>/agent-scrum-kit     # im Kit-Ordner, nicht im Projekt
export KIT_ROLE=engineer-a
export KIT_HOST=claude-code
claude
```

## 2. Rollendatei laden

Zwei Eingaben je Session. Die erste liest einmal ein:

```
Lies roles/_COMMON.md und roles/engineer.md und uebernimm die Rolle engineer-a.
Fuehre dann bin/tick.sh aus und arbeite nach dem, was er dir zeigt.
Ein Ticket zur Zeit. Spawne niemals einen Subagenten.
```

Die zweite haelt die Rolle im Dauerbetrieb. `/loop` ohne Intervall laesst das Modell sich
selbst takten; jede Runde beginnt mit dem Tick und liest die Rollenblaetter nicht neu:

```
/loop Fuehre bin/tick.sh aus und arbeite danach deine Rolle laut roles/engineer.md weiter. Ein Ticket zur Zeit. Kein Subagent.
```

Der watchdog bekommt ein festes Intervall, weil seine Arbeit reines Messen ist:

```
/loop 5m Fuehre bin/tick.sh aus, dann eine watchdog-Runde laut roles/watchdog.md: budget.sh, die Blicke, commit.sh.
```

Die vollstaendige Liste je Rolle steht in `README.md` im Abschnitt "Team starten".

## 3. Session-Kennung

Claude Code setzt `CLAUDE_CODE_SESSION_ID` in jeder Session. Der Wert ist der Dateiname
des Transkripts unter `~/.claude/projects/<projekt-slug>/<kennung>.jsonl`, das
`bin/budget.sh` liest. Gemessen am 2026-09-10.

`session-id.sh` nimmt `KIT_SESSION_ID`, sonst `CLAUDE_CODE_SESSION_ID`, sonst scheitert es.
Es leitet die Kennung **nie** aus der juengsten Transkriptdatei ab: bei parallelen Sessions
gehoert die juengste Datei der Session, die zuletzt geschrieben hat, nicht der eigenen.

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
