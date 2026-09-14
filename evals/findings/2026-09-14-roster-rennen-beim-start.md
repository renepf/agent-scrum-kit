---
role: bin/register.sh
case: 69-register-nine-parallel (neu), gefunden durch den Starttest mit neun echten Sessions
date: 2026-09-14
---
Beobachtet: Neun claude-Sessions starteten parallel, jede lief `bin/tick.sh` → `register.sh`. Danach
hatte `roster.md` 4 von 9 Zeilen. Anker (`.pid-roles/`) und Leases waren fuer alle neun richtig.

Erwartet: neun Zeilen. `bin/budget.sh` liest den Roster — fehlende Rollen misst der watchdog nie.

Ursache: **fehlende Regel im Werkzeug, und eine Luecke in der Suite.** `register.sh` hielt nur die
Sperre je Rolle (`.lease-<rolle>.lock`), `roster.md` ist aber fuer alle Rollen geteilt. Neun
gleichzeitige Lese-Aendern-Schreib-Laeufe unter neun verschiedenen Sperren ueberschrieben einander.
Kein Eval-Fall startete mehrere Rollen gleichzeitig.

Beleg: Fall 69 gegen den alten Code, drei Laeufe: `roster.md: 2/9`, `1/9`, `1/9` Zeilen.

Erledigt: zweite, geteilte Sperre `roster.md.lock`. Der erste Versuch verschachtelte beide Sperren und
brach Fall 62 (Zwillingssperre): `with_lock` setzt eine Aufraeum-trap, die innere ueberschrieb die
aeussere, und ein `die` in der Zwillingspruefung liess die Lease-Sperre liegen. Jetzt nacheinander,
nie verschachtelt. Fall 69 dreimal 9/9, Fall 62 gruen, Mutation (Roster-Sperre entfernt) → rot.
Kein Rollenblatt geaendert.
