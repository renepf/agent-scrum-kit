# Team starten

Die vollstaendige Startanleitung — Reihenfolge, erste Eingabe je Rolle, Dauerbetrieb,
Reset — steht in `README.md`, Abschnitt 2. Wie eine Session auf deinem Host startet, steht in
`adapters/<host>/README.md`. Dieses Blatt haelt nur fest, was hostunabhaengig gilt.

## Reihenfolge

1. `product-owner` und `simplicity-reviewer` — der PO braucht das Verdict vor `planned`.
2. `watchdog` — misst von Anfang an, committet als Einziger.
3. alle uebrigen in beliebiger Reihenfolge.

## Rollen und Blaetter

| Rolle | Blatt | Warteschlange |
|---|---|---|
| `product-owner` | `roles/product-owner.md` | alle Zustaende |
| `simplicity-reviewer` | `roles/simplicity-reviewer.md` | `rfr` |
| `watchdog` | `roles/watchdog.md` | keine |
| `engineer-a` | `roles/engineer.md` | `planned` |
| `engineer-b` | `roles/engineer.md` | `planned` |
| `qa-ruthless` | `roles/qa-ruthless.md` | `rfr` |
| `security-engineer` | `roles/security-engineer.md` | `rfr` |
| `acceptance-tester` | `roles/acceptance-tester.md` | `rft` |
| `merge-gate` | `roles/merge-gate.md` | `in-testing` |

Jede Session beginnt mit `roles/_COMMON.md` und ihrem Blatt, dann `bin/tick.sh` — und
danach in **jeder** Runde zuerst `bin/tick.sh`. Wartet eine Rolle auf den ersten Sprint, ist
das kein Fehler: der Tick meldet es und registriert sie nach dem Sprintschnitt von selbst.

Der `kit-maintainer` laeuft nicht mit. Er startet nur, wenn in `evals/findings/` ein Fall
liegt oder ein Eval-Fall durchfaellt.
