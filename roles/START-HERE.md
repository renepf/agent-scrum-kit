# Team starten

Jede Rolle ist eine eigene Session in einem eigenen Terminalfenster. Wie eine Session auf deinem
Host startet und wie der Dauerbetrieb dort heisst, steht in `adapters/<host>/README.md`.
Die Einrichtung davor steht in `INSTALL.md`.

## Reihenfolge

| Schritt | Terminal | `export KIT_ROLE=` | Rollendatei | Intervall |
|---|---|---|---|---|
| 1 | 1 | `product-owner` | `roles/product-owner.md` | 10 min |
| 1 | 2 | `simplicity-reviewer` | `roles/simplicity-reviewer.md` | 5 min |
| 2 | 3 | `watchdog` | `roles/watchdog.md` | 5 min |
| 3 | 4 | `engineer-a` | `roles/engineer.md` | 5 min |
| 3 | 5 | `engineer-b` | `roles/engineer.md` | 5 min |
| 3 | 6 | `qa-ruthless` | `roles/qa-ruthless.md` | 5 min |
| 3 | 7 | `security-engineer` | `roles/security-engineer.md` | 5 min |
| 3 | 8 | `acceptance-tester` | `roles/acceptance-tester.md` | 10 min |
| 3 | 9 | `merge-gate` | `roles/merge-gate.md` | 10 min |

Warum so: der product-owner braucht vor `planned` das Verdict des simplicity-reviewer, und erst
sein `sprint-new.sh` legt den Sprint an. Der watchdog misst ab dem ersten Ticket. Alle anderen
duerfen sofort starten — ihr Tick meldet "kein aktiver Sprint" und endet normal.

Der `kit-maintainer` laeuft nicht mit. Er startet nur, wenn in `evals/findings/` etwas liegt oder
ein Eval-Fall durchfaellt.

## Prompt je Runde, host-neutral

```
Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite deine Rolle
laut <rollendatei>: ein Ticket zur Zeit, aufgreifen heisst sofort den In-Status setzen, kein Subagent.
```

watchdog zusaetzlich: `… danach bin/budget.sh, vier Blicke, bin/commit.sh.`

## Ohne Menschen neu starten

Laeuft eine Rolle unter der Waechter-Schleife ihres Hosts (`adapters/<host>/role-loop.sh`), beendet
sie sich bei `STOP` selbst mit `bin/restart-self.sh stop` und die Schleife startet sie frisch. Das
Skript beendet nichts, solange Uebergabe oder Ticketgrenze fehlen.

## Wenn eine Session an ihrem Limit ist

`bin/brain.sh handover` schreiben, Kontext leeren (**neue Session, nicht verdichten**), denselben
Prompt erneut. Der naechste Tick registriert die neue Session-ID und zeigt die Uebergabe.

## Wenn der Tick "zweite Instanz" meldet

Diese Rolle laeuft schon in einem anderen Prozess. Die neue Session beenden, nicht die alte.
Erst wenn die alte wirklich beendet ist, uebernimmt die neue beim naechsten Tick.
