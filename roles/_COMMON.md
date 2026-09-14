# Gemeinsame Regeln fuer jede Rolle

Lies zuerst `AGENTS.md` (der Arbeitsvertrag), dann `protocols/LOOP.md`.
Dieses Blatt ist die Kurzfassung fuer den Alltag. Bei Widerspruch gilt `protocols/LOOP.md`.

## Eiserne Regel

Eine Rolle ist eine Session im Haupt-Thread und **spawnt niemals einen Subagenten**.
Ein Ticket zur Zeit. Nebenlaeufigkeit entsteht ausschliesslich dadurch, dass mehrere
Sessions parallel laufen — nie innerhalb einer Session.

## Jede Runde beginnt mit dem Tick

```bash
bin/tick.sh
```

Der Tick registriert dich, erneuert deine Zwillingssperre, holt nach einem Reset dein
Gedaechtnis zurueck und zeigt in dieser Reihenfolge: Rueckweisungen, deine Tickets, freie Tickets
aus deiner Warteschlange, neue Chat-Zeilen, Erwaehnungen `@<deine-rolle>`, deinen Tokenstand.
**Zeigt er nichts fuer dich, endet die Runde sofort.** Eine leere Runde kostet einen Tick.

Bricht der Tick mit "zweite Instanz" ab, laeuft deine Rolle schon in einem anderen Prozess.
Diese Session beenden. Nicht umgehen.

## Werkzeuge

| Zweck | Befehl |
|---|---|
| Lagebild | `bin/tick.sh` |
| Ticket aufnehmen oder weiterreichen | `bin/status.sh <nr> <status> "<einzeiler>"` |
| als weiterer Pruefer in `in-review` einsteigen | `bin/claim.sh <nr>` |
| mergen und `done` setzen | `bin/merge.sh <nr>` (product-owner; merge-gate nur mit `PO OK`) |
| mitteilen, jemanden ansprechen | `bin/say.sh "#<nr> · <betreff>" <<'EOF' … EOF` |
| Gedaechtnis | `bin/brain.sh note · share · forget · doc · handover · log · recall` |

## Ready heisst wartend, In heisst aktiv

`rfr` und `rft` sagen: fertig fuer die naechste Stufe, **niemand** arbeitet daran. `in-review`
und `in-testing` sagen: eine Rolle arbeitet **jetzt** daran. Wer ein Ticket aufgreift, setzt
**sofort** den In-Status — auch der zweite Pruefer (`claim.sh`), wenn der erste schon drin ist.

## Verdicts

Ein Verdict ist ein PR-Kommentar, dessen **erste Zeile** so beginnt:

```
<VERDICT> — HEAD `<sha8>`, <kurzer Befund>
```

`<sha8>` sind die ersten acht Zeichen des aktuellen PR-HEAD. Ein Push nach deinem Verdict
entwertet es; `status.sh` und `merge.sh` pruefen das maschinell.

## Gedaechtnis — ueberlebt jeden Reset

| Was | Wann | Befehl |
|---|---|---|
| Journal | nach jedem Schritt: aufgenommen, rot/gruen, PR, Verdict | `brain.sh log "#<nr> · <betreff>"` |
| Fakt fuer dich | etwas, das du nicht neu messen willst | `TYPE=project brain.sh note <slug> "<beschreibung>"` |
| Fakt fuer alle | eine andere Rolle koennte denselben Fehler machen | `brain.sh share <slug> "<beschreibung>"` |
| falsch gewordener Fakt | sofort | `brain.sh forget <slug>` oder dieselbe `note` neu schreiben |
| Uebergabe | vor jedem Reset und bei `STOP` | `brain.sh handover "<beschreibung>"` |

Regeln: `memory/README.md`. Das Skript lehnt Dubletten, relative Datumsangaben und falsche
Typen ab. `INDEX.md` ist generiert.

## Was du nie tust

- **Keine Subagenten spawnen.** Siehe eiserne Regel oben.
- **Nie auf dem Integrationsbranch arbeiten.** Ein Worktree je Ticket.
- **Nie Status, Label oder Besitz von Hand setzen.** Wer ein Ticket haelt, zeigt `owner:<rolle>`,
  nicht der Assignee — alle Sessions teilen oft einen Account.
- **Nie das Kit-Repo committen.** Das macht nur der watchdog im Takt.
- **Nie aus einem fehlgeschlagenen Befehl einen Zustand ableiten.** Melden, nicht raten.
- **Nie erfinden.** Fehlt dir eine Angabe, schreibst du `UNKNOWN — pruefen unter <pfad>`.
- **Nie deine eigene Jobbeschreibung aendern.** Das darf nur der `kit-maintainer`, als Pull
  Request, den ein Mensch merged.

## Wann du aufhoerst

`Warnung` im Tick: kein neues Ticket. `STOP`: an der naechsten Ticketgrenze `brain.sh handover`
(Ticket, Stand, SHA, naechster Schritt, offene Fragen) plus eine Zeile per `say.sh`, dann Kontext
leeren — **nicht verdichten**. Laeufst du unter der Waechter-Schleife (der Tick sagt es dir), heisst
das `bin/restart-self.sh stop`; sonst bittest du den Menschen um den Reset. Nach einem Reset kennt der
Tick deine Rolle weiter und zeigt dir die Uebergabe. Spaetestens nach `KIT_MAX_TICKETS` Tickets.

## Ton

Befund, Messwert mit Zeit, SHA. Eine Behauptung ohne Messung wird als solche benannt.
