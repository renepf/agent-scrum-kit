# Gemeinsame Regeln fuer jede Rolle

Lies zuerst `AGENTS.md` (der Arbeitsvertrag), dann `protocols/LOOP.md`.
Dieses Blatt ist die Kurzfassung fuer den Alltag. Bei Widerspruch gilt `protocols/LOOP.md`.

## Eiserne Regel

Eine Rolle ist eine Session im Haupt-Thread und **spawnt niemals einen Subagenten**.
Ein Ticket zur Zeit. Nebenlaeufigkeit entsteht ausschliesslich dadurch, dass mehrere
Sessions parallel laufen — nie innerhalb einer Session.

## Beim Start jeder Session

Die Session laeuft im Kit-Ordner — nur dort stimmen die Pfade `bin/`, `roles/` und
`sprints/`. Im Projekt arbeitest du ueber Worktrees unter `KIT_WORKTREE_ROOT`.

```bash
export KIT_ROLE=<deine-rolle>
bin/tick.sh
```

## Der Tick — dein einziger Lagebericht

`bin/tick.sh` ist idempotent und liefert in einem Aufruf alles, was du zum Weiterarbeiten
brauchst:

1. registriert dich, falls noetig — auch nach einem Reset, wenn deine Session-ID neu ist
2. zeigt die Chat-Eintraege, die du noch nicht gesehen hast
3. zeigt, was davon **direkt an dich** gerichtet ist (`@<deine-rolle>` in einer fremden Chatdatei)
4. zeigt deine Warteschlange — nur die Zustaende, die deine Rolle laut `KIT_QUEUES` aufnimmt
5. zeigt deinen Kontextstand und ein etwaiges `STOP`

Gibt es noch keinen Sprint, sagt es das und endet normal. Warten ist kein Fehler.

**Du rufst `bin/tick.sh` in JEDER Runde auf, bevor du irgendetwas anderes tust.**
Es ersetzt `register.sh` und das Lesen von `INDEX.md` von Hand. Die Rollenblaetter liest du
nur beim Start einmal, nicht in jeder Runde.

## Deine Werkzeuge

| Zweck | Befehl |
|---|---|
| Lage abfragen | `bin/tick.sh` — in jeder Runde als Erstes |
| etwas mitteilen | `bin/say.sh "#<nr> · <betreff>" <<'EOF' … EOF` |
| Ticket weiterreichen | `bin/status.sh <nr> <zustand> "<einzeiler>"` |
| in eine Quelle springen | `sed -n '<zeile>,+20p' sprints/<sprint>/chat/<rolle>.md` |

## Jemanden ansprechen

Schreib `@<rolle>` in deinen Chat-Eintrag. Der naechste Tick dieser Rolle zeigt die Zeile
unter "direkt an dich gerichtet" — genau einmal. So wird jede Uebergabe ausgeloest, die kein
Statuswechsel ist. **Es gibt keinen Menschen, der Nachrichten weiterreicht.**

Ein Statuswechsel per `status.sh` braucht keine Ansprache: das Ticket landet von selbst in
der Warteschlange der Rolle, die diesen Zustand aufnimmt.

Du schreibst **nur** in `chat/<deine-rolle>.md`, und nur per `say.sh`. Nie in die Datei einer
anderen Rolle, nie in `INDEX.md`, `roster.md` oder `budget.md` — die sind generiert.

## Was du nie tust

- **Keine Subagenten spawnen.** Siehe eiserne Regel oben.
- **Nie auf dem Integrationsbranch arbeiten.** Ein Worktree je Ticket.
- **Nie Board-Status oder Status-Label von Hand setzen.** Immer `bin/status.sh` — es
  schreibt beides zusammen, deshalb koennen sie nicht auseinanderlaufen.
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
