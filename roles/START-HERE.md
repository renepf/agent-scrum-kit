# Starting the team

Every role is its own session in its own terminal window. How a session starts on your
host, and what continuous operation is called there, is in `adapters/<host>/README.md`.
The setup before that is in `INSTALL.md`.

## Order

| Step | Terminal | `export KIT_ROLE=` | Role file | Interval |
|---|---|---|---|---|
| 1 | 1 | `product-owner` | `roles/product-owner.md` | 10 min |
| 1 | 2 | `simplicity-reviewer` | `roles/simplicity-reviewer.md` | 5 min |
| 1 | 3 | `requirements-engineer` | `roles/requirements-engineer.md` | 10 min |
| 2 | 3 | `watchdog` | `roles/watchdog.md` | 5 min |
| 3 | 4 | `engineer-a` | `roles/engineer.md` | 5 min |
| 3 | 5 | `engineer-b` | `roles/engineer.md` | 5 min |
| 3 | 6 | `qa-ruthless` | `roles/qa-ruthless.md` | 5 min |
| 3 | 7 | `security-engineer` | `roles/security-engineer.md` | 5 min |
| 3 | 8 | `acceptance-tester` | `roles/acceptance-tester.md` | 10 min |
| 3 | 9 | `merge-gate` | `roles/merge-gate.md` | 10 min |

Why this order: before `planned` the product-owner needs the verdict of the simplicity-reviewer,
and only their `sprint-new.sh` creates the sprint. The watchdog measures from the first ticket on.
Everybody else may start at once — their tick reports "no active sprint" and ends normally.

The `kit-maintainer` does not run along. It starts only when something lies in `evals/findings/` or
an eval case fails.

## Prompt per round, host-neutral

```
Run bin/tick.sh. If nothing is waiting for you, end the round. Otherwise work your role
per <role file>: one ticket at a time, picking up means setting the In status immediately, no subagent.
```

watchdog additionally: `… afterwards bin/budget.sh, four looks, bin/commit.sh.`

## Restarting without a human

On `STOP` a role resets itself with `bin/restart-self.sh stop`. If it runs under the
watchdog loop of its host (`adapters/<host>/role-loop.sh`), the loop starts it fresh; if it runs
in a terminal multiplexer without a loop, the script opens the loop in a new tab. In the middle of a
ticket this is allowed when the handover names every held ticket. If the handover, a named ticket or
a restart path is missing, the script ends nothing.

## When a session is at its limit

Write `bin/brain.sh handover`, clear the context (**a new session, do not compact**), the same
prompt again. The next tick registers the new session id and shows the handover.

## When the tick reports "second instance"

This role already runs in another process. End the new session, not the old one.
Only when the old one has really ended does the new one take over at the next tick.
