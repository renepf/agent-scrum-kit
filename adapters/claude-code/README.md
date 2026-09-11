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

## 3. Session-Kennung und Host-PID

- **Session-Kennung:** Claude Code setzt `CLAUDE_CODE_SESSION_ID` in jeder Session. Der Wert ist der
  Dateiname des Transkripts unter `~/.claude/projects/<projekt-slug>/<kennung>.jsonl`
  (gemessen 2026-09-10). `session-id.sh` liest nur diese Variable. **Nicht** aus der juengsten
  Transkriptdatei ableiten: bei neun parallelen Sessions gehoert sie der Session, die zuletzt
  geschrieben hat.
- **Host-PID** fuer die Zwillingssperre: `host-pid.sh` geht die Prozesskette hoch bis zum Prozess
  `claude` (gemessen 2026-09-10: Skript → Shell des Werkzeugaufrufs → `claude`). Die PID bleibt ueber
  alle Werkzeugaufrufe einer Session gleich.

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
