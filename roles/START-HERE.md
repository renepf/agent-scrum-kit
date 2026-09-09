# Team starten

Jede Rolle ist eine eigene Session in einem eigenen Terminalfenster. Wie eine Session auf
deinem Host startet, steht in `adapters/<host>/README.md` — nicht hier.

Reihenfolge: erst `product-owner` (schneidet den Sprint), dann `watchdog`, dann der Rest.

| Terminal | Umgebung | Rollendatei |
|---|---|---|
| 1 | `export KIT_ROLE=product-owner` | `roles/product-owner.md` |
| 2 | `export KIT_ROLE=watchdog` | `roles/watchdog.md` |
| 3 | `export KIT_ROLE=engineer-a` | `roles/engineer.md` |
| 4 | `export KIT_ROLE=engineer-b` | `roles/engineer.md` |
| 5 | `export KIT_ROLE=qa-ruthless` | `roles/qa-ruthless.md` |
| 6 | `export KIT_ROLE=simplicity-reviewer` | `roles/simplicity-reviewer.md` |
| 7 | `export KIT_ROLE=security-engineer` | `roles/security-engineer.md` |
| 8 | `export KIT_ROLE=acceptance-tester` | `roles/acceptance-tester.md` |
| 9 | `export KIT_ROLE=merge-gate` | `roles/merge-gate.md` |

Erster Prompt in jeder Session, sinngemaess:
`Lies <rollendatei> und uebernimm die Rolle <rolle>.`

Der `kit-maintainer` laeuft nicht mit. Er startet nur, wenn in `evals/findings/` etwas liegt
oder ein Eval-Fall durchfaellt.

## Einmalig, vor dem ersten Start

```bash
cp kit.env.example kit.env     # und ausfuellen
bin/preflight.sh               # muss "preflight ok" drucken
evals/run.sh                   # muss gruen sein
```

## Wenn eine Session an ihrem Limit ist

Sie schreibt ihre Uebergabe per `say.sh`, leert den Kontext (**neue Session, nicht
verdichten**), und bekommt denselben ersten Prompt erneut. `bin/register.sh` traegt die neue
Session-Kennung in `roster.md` ein, der Watchdog findet sie wieder.
