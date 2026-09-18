# Common rules for every role

Read `AGENTS.md` first (the working contract), then `protocols/LOOP.md`.
This sheet is the short form for daily work. On a contradiction, `protocols/LOOP.md` wins.

## Iron Rule

A role is one session in the main thread and **never spawns a subagent**.
One ticket at a time. Concurrency comes only from several sessions running in
parallel — never from inside one session.

## Every round starts with the tick

```bash
bin/tick.sh
```

The tick registers you, renews your twin lock, pulls your memory back after a reset
and shows, in this order: rejections, your tickets, free tickets from your queue,
new chat lines, mentions of `@<your-role>`, your token state.
**If it shows nothing for you, the round ends immediately.** An empty round costs one tick.

If the tick aborts with "second instance", your role is already running in another process.
End this session. Do not work around it.

## Tools

| Purpose | Command |
|---|---|
| situation | `bin/tick.sh` |
| pick up a ticket or hand it on | `bin/status.sh <nr> <status> "<one-liner>"` |
| join `in-review` as a further reviewer | `bin/claim.sh <nr>` |
| merge and set `done` | `bin/merge.sh <nr>` (product-owner; merge-gate only with `PO OK`) |
| tell something, address somebody | `bin/say.sh "#<nr> · <subject>" <<'EOF' … EOF` |
| memory | `bin/brain.sh note · share · forget · doc · handover · log · recall` |

## Ready means waiting, In means active

`rfr` and `rft` say: finished for the next stage, **nobody** works on it. `in-review`
and `in-testing` say: a role works on it **now**. Whoever picks a ticket up sets the
In status **immediately** — the second reviewer too (`claim.sh`), when the first is already in.

## Verdicts

A verdict is a PR comment whose **first line** starts like this:

```
<VERDICT> — HEAD `<sha8>`, <short finding>
```

`<sha8>` are the first eight characters of the current PR HEAD. A push after your verdict
invalidates it; `status.sh` and `merge.sh` check that mechanically.

## Memory — survives every reset

| What | When | Command |
|---|---|---|
| journal | after every step: picked up, red/green, PR, verdict | `brain.sh log "#<nr> · <subject>"` |
| fact for you | something you do not want to measure again | `TYPE=project brain.sh note <slug> "<description>"` |
| fact for everybody | another role could make the same mistake | `brain.sh share <slug> "<description>"` |
| fact that turned wrong | at once | `brain.sh forget <slug>` or write the same `note` again |
| handover | before every reset and on `STOP` | `brain.sh handover "<description>"` |

Rules: `memory/README.md`. The script rejects duplicates, relative dates and wrong
types. `INDEX.md` is generated.

## What you never do

- **Never spawn subagents.** See the iron rule above.
- **Never work on the integration branch.** One worktree per ticket.
- **Never set status, label or ownership by hand.** Whoever holds a ticket shows `owner:<role>`,
  not the assignee — all sessions often share one account.
- **Never commit the kit repo.** Only the watchdog does that, on its interval.
- **Never derive a state from a failed command.** Report, do not guess.
- **Never invent.** If a detail is missing, you write `UNKNOWN — check at <path>`.
- **Never end your own loop** — not on a warning, not on STOP, not on your own estimate, not because
  other roles are silent. In the reference loop every role ended its loop and waited for a human;
  the whole team stood still for three days. An empty round costs one tick, a stalled loop costs everything.
- **Never ask a question that waits for input.** It halts your session until a human looks into your
  terminal. Ask with `say.sh "… · @owner"`, take the safe default until the answer arrives, name
  the default, keep ticking.
- **Never change your own job description.** Only the `kit-maintainer` may, as a pull
  request that a human merges.

## When you stop

`warning` in the tick: no new ticket. `STOP`: at the next ticket boundary `brain.sh handover`
(ticket, state, SHA, next step, open questions) plus one line via `say.sh`, then clear the
context — **do not compact it**. `bin/restart-self.sh stop` resets you yourself as soon as a
watchdog loop or a terminal multiplexer can start you again (the tick tells you); otherwise you ask
the human. In the middle of a ticket this is allowed: the handover then names every held `#<nr>` with
state, SHA and next step — without that the script refuses. After a reset the tick still knows
your role and shows you the handover. At the latest after `KIT_MAX_TICKETS` tickets.

## Tone

Finding, measured value with a time, SHA. A claim without a measurement is named as one.
