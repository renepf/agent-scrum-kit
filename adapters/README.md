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
| `claude-code` | vollstaendig: Session-ID, Host-PID und Transkripte gemessen 2026-09-10 |
| `cursor` | Start belegt (`cursor-agent --help`); Session-ID, Host-PID, Transkripte UNKNOWN |
| `codex` | Startbefehl UNKNOWN — nicht installiert, nicht geprueft |
| `qwen-code` | start, session file, processes, end and transcripts measured 2026-09-15 against a local model; everything that needs a tool call is not measured, because no local model on the build machine produced one |
| `pi` | same state as `qwen-code`: measured 2026-09-15 against a local model, tool-call paths not measured |
| `hermes` | UNKNOWN — Startbefehl, Sessionkennung und Werkzeugnamen beim Owner erfragen |

Jeder Adapter liefert drei ausfuehrbare Pflichtdateien:

- `session-id.sh` — druckt die Session-Kennung auf stdout, oder scheitert mit Exitcode ≠ 0.
  **Scheitern ist erlaubt. Raten nicht.**
- `host-pid.sh` — druckt die PID des Host-Prozesses dieser Session, fuer die Zwillingssperre.
  Scheitert er, warnt die Sperre nur (`UNKNOWN`) und blockiert nicht.

Optional, nur wo der Adapter es weiss:

- `host-alive.sh <pid>` — Exit 0 nur, wenn unter der PID ein **Host**-Prozess lebt. Ohne diese Datei
  gilt `kill -0`, und eine neu vergebene PID eines fremden Prozesses zaehlt als lebende Rolle.
- `is-background.sh` — Exit 0, wenn die Session eine Hintergrund-Session ist, die die Rolle nur geerbt
  hat. Dann schweigt der Start-Hook und `bin/tick.sh` endet mit Exit 3.
- `start.sh <role>` — starts a session for a role (`qwen-code`, `pi`). Both refuse to start unless
  `bin/local-model-check.sh` passes for `KIT_LOCAL_MODEL`, and export `KIT_SESSION_ID` and `KIT_HOST_PID`
  before they replace themselves with the host.
- `transcript-path.sh <session-id>` — druckt die Pfade der Transkripte, einen je Zeile.
  Schreibt der Host keine Transkripte, ist die Datei nicht ausfuehrbar oder scheitert —
  dann traegt `budget.md` `UNKNOWN` ein und die Rolle faellt auf die Notbremse zurueck
  (Ruhestand nach `KIT_MAX_TICKETS` Tickets).
