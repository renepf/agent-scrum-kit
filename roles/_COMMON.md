# Gemeinsame Regeln fuer jede Rolle

Lies zuerst `AGENTS.md` (der Arbeitsvertrag), dann `protocols/LOOP.md`.
Dieses Blatt ist die Kurzfassung fuer den Alltag. Bei Widerspruch gilt `protocols/LOOP.md`.

## Eiserne Regel

Eine Rolle ist eine Session im Haupt-Thread und **spawnt niemals einen Subagenten**.
Ein Ticket zur Zeit. Nebenlaeufigkeit entsteht ausschliesslich dadurch, dass mehrere
Sessions parallel laufen — nie innerhalb einer Session.

## Beim Start jeder Session, in dieser Reihenfolge

```bash
cd "$KIT_WORKTREE_ROOT"
export KIT_ROLE=<deine-rolle>
bin/preflight.sh            # Ticket-Backend erreichbar? Fehlschlag = stoppen und melden.
bin/register.sh             # Session-ID in roster.md
tail -60 sprints/$(cat sprints/CURRENT)/INDEX.md
```

## Deine drei Werkzeuge

| Zweck | Befehl |
|---|---|
| etwas mitteilen | `bin/say.sh "#<nr> · <betreff>" <<'EOF' … EOF` |
| Ticket weiterreichen | `bin/status.sh <nr> <status> "<einzeiler>"` |
| Schwarmwissen lesen | `tail -60 …/INDEX.md`, dann `sed -n '<zeile>,+20p' …/chat/<rolle>.md` |

Du schreibst **nur** in `chat/<deine-rolle>.md`, und nur per `say.sh`. Nie in die Datei einer
anderen Rolle, nie in `INDEX.md`, `roster.md` oder `budget.md` — die sind generiert.

## Was du nie tust

- **Keine Subagenten spawnen.** Siehe eiserne Regel oben.
- **Nie auf dem Integrationsbranch arbeiten.** Ein Worktree je Ticket.
- **Nie ein Status-Label von Hand setzen.** Immer `bin/status.sh`.
- **Nie das Kit-Repo committen.** Das macht nur der watchdog im Takt.
- **Nie aus einem fehlgeschlagenen Befehl einen Zustand ableiten.** Ein Fehlschlag ist ein
  Fehlschlag, kein Ergebnis. Melden, nicht raten.
- **Nie erfinden.** Fehlt dir eine Angabe, schreibst du `UNKNOWN — pruefen unter <pfad>`.
- **Nie deine eigene Jobbeschreibung aendern.** Das darf nur der `kit-maintainer`, und nur
  als Pull Request, den ein Mensch merged.

## Wann du aufhoerst

Nach jedem abgeschlossenen Ticket liest du `budget.md`:

- **Warnung** fuer dich: kein neues Ticket mehr annehmen
- **STOP <deine-rolle>**: Uebergabe per `say.sh`, dann Kontext leeren und die Startfolge erneut
- unabhaengig davon: nach `KIT_MAX_TICKETS` Tickets ohnehin Ruhestand

Kontext leeren heisst **neue Session**, nicht verdichten. Verdichten verliert die technischen
Details, an denen die naechste Runde haengt.

Die Uebergabe enthaelt: Ticketnummer, Stand, SHA, was als naechstes ansteht. Kein Fliesstext.

## Ton

Befund, Messwert, SHA. Ein Messwert bekommt einen Zeitstempel; eine Behauptung ohne Messung
wird als solche benannt.
