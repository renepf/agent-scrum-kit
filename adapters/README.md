# Adapter — wie eine Session auf deinem Host startet

Die Jobbeschreibungen unter `roles/` sind reines Markdown und kennen keinen Host. Ein
Adapter legt genau drei Dinge fest:

1. **wie eine Session gestartet wird**
2. **wie sie eine Rollendatei laedt**
3. **wie die Session-Kennung fuer den Watchdog zu ermitteln ist**

Mehr gehoert nicht hinein. Kommt ein Adapter ohne eine dieser Angaben aus dem Owner-Wissen
nicht aus, steht dort `UNKNOWN — <wo zu klaeren>`. Ein erfundener Startbefehl ist der
schlimmste Fehler, den dieses Repo machen kann.

| Adapter | Zustand |
|---|---|
| `claude-code` | vollstaendig, auf dieser Maschine verifiziert |
| `cursor` | Start verifiziert, Transkripte UNKNOWN |
| `codex` | Startbefehl UNKNOWN — nicht installiert, nicht geprueft |
| `pi` | UNKNOWN — Startbefehl, Sessionkennung und Werkzeugnamen beim Owner erfragen |
| `hermes` | UNKNOWN — Startbefehl, Sessionkennung und Werkzeugnamen beim Owner erfragen |

Jeder Adapter liefert zwei ausfuehrbare Dateien:

- `session-id.sh` — druckt die Session-Kennung auf stdout, oder scheitert mit Exitcode ≠ 0.
  **Scheitern ist erlaubt. Raten nicht.**
- `transcript-path.sh <session-id>` — druckt die Pfade der Transkripte, einen je Zeile.
  Schreibt der Host keine Transkripte, ist die Datei nicht ausfuehrbar oder scheitert —
  dann traegt `budget.md` `UNKNOWN` ein und die Rolle faellt auf die Notbremse zurueck
  (Ruhestand nach `KIT_MAX_TICKETS` Tickets).
