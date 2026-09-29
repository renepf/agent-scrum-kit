# LOOP — operating protocol of the agent team

Host-independent. How a session **starts** is in `adapters/<host>/README.md`.
How the team is set up is in `INSTALL.md`.

## 1. Principle

Every role is its own session in its own terminal, with its own context window.
**No subagents are spawned.** Every session works in the main thread on exactly one
ticket at a time, and per role exactly **one** process runs.

Two truths, strictly separated:

| What | Where | Who writes |
|---|---|---|
| **Ticket status** — where the ticket stands | status field of the GitHub Project (`KIT_BOARD=github-project`), the label as a mirror | only `bin/status.sh` |
| **Ownership** — who holds it right now | label `owner:<role>` | only `bin/status.sh` |
| **Reasoning, findings, cross-talk** | `sprints/<sprint>/chat/<role>.md` | every role only its own file |

The chat **never** decides whose turn it is. If the chat fails, the loop runs on.

Ownership hangs on the label, not on the assignee: all sessions often share **one** account, and the
assignee cannot tell `engineer-a` and `engineer-b` apart.

## 2. Status model — eight states

| # | Key | Board | Meaning | Ownership (`owner:`) | On when |
|---|---|---|---|---|---|
| 1 | `backlog` | Backlog | the ticket exists, not cut yet | — (product-owner) | story + ACs stand, solution path agreed |
| 2 | `planned` | Planned | in the sprint, ready to be picked up | **nobody** | an engineer picks it up |
| 3 | `in-progress` | In progress | implementation is running | exactly **one** engineer | finished **and** the PR open |
| 4 | `rfr` | RfR | Ready for Review — waiting | **nobody** | a reviewer picks it up |
| 5 | `in-review` | In review | the reviewing engineer works **actively** | an engineer that did **not** build it | all three PASS for the current HEAD, each naming its reviewer |
| 6 | `rft` | RfT | Ready for Testing — waiting | **nobody** | the reviewing engineer picks it up |
| 7 | `in-testing` | In Testing | acceptance test against the running build | the reviewing engineer | ACCEPTANCE PASS, MERGE-GATE OK, the PO decision |
| 8 | `done` | Done | merged and closed, **no** label | — | — |

**Ready means waiting, In means active.** Whoever picks a ticket up sets the
In status **immediately**. One engineer reviews a ticket, not two — one `owner:` label, all four hats.

### Allowed edges — exactly these

```
backlog → planned → in-progress → rfr → in-review → rft → in-testing → done
                        ▲                    │                    │
                        └────────────────────┴────────────────────┘
                                   backward edge
```

| Edge | Who may | Check before writing |
|---|---|---|
| `backlog → planned` | product-owner | **ledger:** `tickets/<nr>/GATES.md` has one gate per `AC-<n>` of the issue |
| `planned → in-progress` | engineer-a, engineer-b | sets `owner:<engineer>` |
| `in-progress → rfr` | the engineer with `owner:` | foreign ownership is refused; **scope:** every file of the PR lies within the approved OWNS revision |
| `rfr → in-review` | a reviewer | sets `owner:<reviewer>`, further reviewers stay |
| `in-review → rft` | a reviewer | **gate:** QA PASS, SIMPLICITY PASS, SECURITY PASS for the current HEAD; every executable gate of the ledger ran green for this HEAD; lint without an error; one QA mutation line per executable gate |
| `rft → in-testing` | an engineer that did not build it | — |
| `in-testing → done` | **product-owner only** | normally through `bin/merge.sh`; `MERGE-GATE OK` of the reviewing engineer for the current HEAD; every gate green or attested; no open `ABANDON` |
| `in-review → in-progress` | a reviewer | `owner:` back to the engineer from the comment history |
| `in-testing → in-progress` | the reviewing engineer or the product-owner | the same |

Every other transition is refused. After a rejection **the same loop runs from the
start**: in-progress → rfr → in-review → rft → in-testing. No shortcut, no "small fix".

### Order in `bin/status.sh`

1. **Check everything before anything is written:** edge, role, ownership, gate. A
   refused transition touches neither the board nor the label nor a comment.
2. **The board first**, then **read the value back**. If it differs or the call fails,
   the script aborts, and the label stays unchanged.
3. The label as a mirror, `owner:` ownership, an issue comment with the role, session id and time, the chat.

### Verdicts hold for one HEAD only

A verdict is a PR comment whose first line starts with `<VERDICT> — HEAD \`<sha8>\``.
A push invalidates every verdict for the old HEAD. `status.sh` and `merge.sh` check that
mechanically.

### Gate ledger per ticket

Before `planned` every ticket has a checkable contract under `tickets/<nr>/GATES.md` (location:
`KIT_TICKETS_DIR`). The issue names every acceptance criterion as its own line
`AC-<n>: <observable result>`, and the ledger has one gate for each of those ids. Format and rules
come from unlazy (MIT); the details are in `bin/gates.py`.

```
# Gates: #<nr> <title>

OWNS: <paths this ticket may change, e.g. src/export/**, tests/export/**>

- [ ] AC-1: <result>
  CHECK: <command that measures the result directly>
  EXPECT: <text only success prints>
  EVIDENCE: pending

- [ ] AC-2: <result only a human sees on the running build>
  EVIDENCE: pending
```

Every `AC-<n>` in the issue text counts, in every spelling, except inside code blocks and HTML comments.

`planned` records `OWNS:` in its issue comment as the line `OWNS Revision 1: \`<globs>\``.
That line is the approval. `rfr` reads only comments whose first line was written by the product-owner,
and takes the highest revision. If somebody changes `OWNS:` in the ledger, that extends
nothing until the product-owner runs `bin/revise.sh <nr> "<globs>" "<reason>"`: the globs in the call
must equal the ledger, and the comment names the old and the new scope and the reason.

OWNS globs: `**` crosses directory boundaries and only as a whole segment, `*` and `?` inside a
name, a trailing `/` means everything below, a path without a glob is exactly one file. Forbidden are
absolute paths, `..` and anything that frees the whole root (`**`, `*`, `./**`). On a
rename the old path counts too.

Two tickets of the same sprint never hold the same file. A path without a glob is one file: it
overlaps with a glob that matches it. Two globs count as separate only when a
literal path segment differs before a glob character stands on either side — so `src/*.py` and
`src/*.kt` count as overlapping. In doubt the kit refuses. A sprint ticket without an approval
holds nothing.

`bin/gates.sh run <nr>` runs every executable gate in the worktree of the PR, only when the
worktree stands on the HEAD of the PR. Green means exit 0 and `EXPECT` in stdout plus stderr; then
`- [x]` and `EVIDENCE: v1 head=<sha8> def=<digest> …` stand there, otherwise `- [ ]` and `EVIDENCE: pending`.
Evidence holds only for this HEAD and this definition of `CHECK`, `EXPECT` and `CWD`: a push
or a changed line invalidates it. Time limit per gate: `KIT_GATE_TIMEOUT` seconds. A
manual gate is attested by the reviewing engineer (never the builder) or the product-owner, for the current HEAD:
`bin/gates.sh attest <nr> <gate> "<evidence>"`. `CHECK` is shell code from the ledger and runs with the
rights of the session that starts it.

An AC that cannot be delivered never falls away silently. Whoever gives it up writes at column 1
`ABANDON: AC-<n> <reason and handover>` into the ledger. Review and run skip that gate;
`merge.sh` and `status.sh <nr> done` refuse with `HANDOFF REQUIRED` while the line stands. The
last word has the product-owner: they take the AC out of issue and ledger with a follow-up ticket, or they
send the ticket back.

`planned` also records the definition of every gate as `GATES Revision 1: \`AC-1=<digest>, …\``
next to `OWNS Revision 1`. Before any check, `merge.sh` prints a merge report: each AC of the issue
exactly once with its ledger state (green or attested for the HEAD, not green with the reason,
ABANDONED, no gate in the ledger), `definition changed since approval` where a digest differs, and
the files in the diff. A failed read shows as `UNKNOWN` in the report. The report is a measurement
for the product-owner, not a check: it rejects nothing.

A limit: as everywhere in the kit, the role comes from `KIT_ROLE` or the anchor. Whoever passes
themselves off as the product-owner can approve. The comment makes that visible in the issue history;
the kit cannot prevent it.

| Check | Where | Refuses when |
|---|---|---|
| reference finding | `status.sh <nr> planned` | `KIT_REFERENCE_CMD` is set and `spec.md` has no `REFERENCE:` line. The `requirements-engineer` runs the command in their own session and records the finding |
| artefact chain | `status.sh <nr> planned` | `tickets/<nr>/intent.md`, `spec.md` or `plan.md` is missing or empty. The `requirements-engineer` writes intent and spec, the plan with the product-owner |
| coverage | `status.sh <nr> planned` | the ledger is missing or formally broken, the issue names no AC, an AC has no gate, the ledger names an AC the issue does not know, the ledger names no or an invalid `OWNS:`, a gate is already ticked or given up via `ABANDON` |
| overlap | `status.sh <nr> planned`, `bin/revise.sh`, `bin/sprint-new.sh` | an OWNS glob can mean the same file as the approval of another open sprint ticket; with `sprint-new.sh` as the ledger of another ticket in the cut |
| lint | `status.sh <nr> planned`, `status.sh <nr> rft` | an oracle cannot fall: `CHECK` prints fixed text, `EXPECT` is a word like `ok` or `fertig`, an `EXPECT` regex looks like a path, `EXPECT` is only a number from the issue. Hints do not refuse and stand in the planned comment: a manual gate, a number in the title of a manual gate, an activity instead of a result, a mostly manual ledger |
| QA mutation per gate | `status.sh <nr> rft` | for an executable gate no `QA PASS` for the current HEAD carries a line `<gate>: mutation <what> → red` |
| green for the HEAD | `status.sh <nr> rft` | an executable gate has no green evidence for the current HEAD, or its definition has changed since the run |
| omission visible | `bin/merge.sh <nr>`, `status.sh <nr> done` | a gate stands on `ABANDON` (`HANDOFF REQUIRED`) |
| attested before the merge | `bin/merge.sh <nr>` | as above, plus a manual gate without evidence for the current HEAD |
| scope | `status.sh <nr> rfr` | no linked PR or more than one, no approval on the issue, the file list is empty or not readable, a file of the PR lies outside the highest approved revision |

### The last word: product-owner

Before `done` two things stand in the PR, both for the current HEAD: `MERGE-GATE OK` from the reviewing engineer, then the
decision of the product-owner. They merge themselves with `bin/merge.sh` — nobody else may, and the
`PO OK` detour is gone with the merge-gate role (owner 2026-09-28). `merge.sh` checks the approvals,
measures CI **fresh**, merges, checks `MERGED` and sets `done`.

## 3. Cast — ten sessions

| Role | Mission | Picks up (`KIT_QUEUE_MAP`) |
|---|---|---|
| `product-owner` | sprint, stories, ACs, cadence, the last word | all |
| `requirements-engineer` | `intent.md` and `spec.md` per ticket, `plan.md` with the product-owner | `backlog` |
| `engineer-a`, `engineer-b`, `engineer-c` | on their own ticket: implementation, TDD, PR. On a foreign one: all four hats — QA, simplicity, security, acceptance — plus the merge report | `planned`, rejections first; `rfr`, `in-review`, `rft`, `in-testing` of the other two |
| `watchdog` | token state, twins, queue, commit | — |

Four eyes in round robin (owner 2026-09-28): `engineer-a` reviews `b` or `c`, `engineer-b` reviews
`a` or `c`, `engineer-c` reviews `a` or `b`. Nobody reviews their own work; `bin/status.sh` turns
the builder away at `in-review`, `rft` and `in-testing`. The handbook per hat stays in
`roles/qa-ruthless.md`, `roles/simplicity-reviewer.md`, `roles/security-engineer.md`,
`roles/acceptance-tester.md` and `roles/merge-gate.md` — they are no longer roles.

Outside the loop: `kit-maintainer` — changes to job descriptions as a pull request.

## 4. Loop order

### Start

1. `product-owner` first: before `planned` the product-owner needs the
   verdict on the solution path, and only `sprint-new.sh` creates `sprints/CURRENT`.
2. `watchdog`, so that budget and twins are measured from the first ticket on.
3. Everybody else right after. They need no special case: `tick.sh` reports "no active
   sprint" and ends with exit 0; as soon as the sprint stands, it registers them at the next tick.

### Every round, every role

1. `bin/tick.sh` — registration and twin lock, after a reset `brain.sh recall`.
2. **Rejections first** (engineers).
3. Continue your own tickets (`owner:<role>`) before picking up a free one.
4. Pick up a free ticket from your own queue — set the In status immediately.
5. None of that: end the round.

### Fixed intervals

| Role | Interval | Reason |
|---|---|---|
| `watchdog` | 5 min | pure measuring, must see STOP and twins in time |
| `engineer-a`, `engineer-b`, `engineer-c` | 5 min | they pick up `planned`, rejections **and** every review state; `rfr` is the most frequent waiting state and the `rft` gate must not be the bottleneck |
| `product-owner` | 10 min | holds the cadence, sees every state |
| `requirements-engineer` | 10 min | works ahead of the sprint; a ticket in the `backlog` does not wait on minutes |

Rounds do not overlap inside one session. A tick costs about two API calls; nine
roles on a 5 to 10 minute cadence stay far below 5 000 calls an hour.

## 4a. Kanban — throughput instead of a pile

Every round the tick measures and shows it to the product-owner: planned, in progress, review queue (`rfr` and
`in-review`), test queue (`rft` and `in-testing`). The numbers are a measurement, not a gate — the decision
is the product-owner's.

| Rule | Value | Why |
|---|---|---|
| planned at least | `KIT_MIN_PLANNED` (7) | an engineer without a free ticket stands still |
| in progress | as many as there are engineers | more creates a pile, fewer leaves capacity idle |
| planning stop | review or test queue above `KIT_QUEUE_STOP` (2) | adding at the front does not help at the back |
| a blocked ticket | report the reason, pick up an unblocked one | waiting is more expensive than switching |

`bin/sprint-new.sh` refuses a ticket without a complete artefact chain, and so does `status.sh <nr> planned`.

## 5. Sprint

A sprint holds `KIT_SPRINT_TICKETS` tickets on a cadence of `KIT_TICKET_MINUTES` minutes, two
engineers in parallel. If one overruns, their next ticket starts at the next grid point.

```
sprints/S-<nnn>-<slug>/
├── sprint.md      # goal, tickets, start, definition of done
├── roster.md      # GENERATED — role, session id, host, host PID
├── INDEX.md       # GENERATED — every chat line chronologically, with file:line
├── budget.md      # GENERATED — context state per session (watchdog)
├── simqueue.md    # who holds an exclusive device right now
├── .lease-<role>  # GENERATED — twin lock: session id, host PID, time
└── chat/<role>.md
```

## 6. Chat — append-only, with a generated index

Every role writes **only** its own file and only appends. Existing lines are **never**
edited — the line numbers in the index must stay valid forever. `bin/say.sh` appends under
a lock and rebuilds `INDEX.md` **completely**, atomically (write to a temporary file, then rename).

## 7. Only one role commits

Every session runs on the same machine in the same folder and sees the others at once. Git is only
history. Nine parallel `git pull --rebase` would be the only real source of conflict — that is why
only the `watchdog` commits, on its interval, with `bin/commit.sh`.

## 8. Twin lock

Per role exactly one process runs. `register.sh` (called by the tick) writes
`.lease-<role>` with the session id, the host PID and a time. If the recorded PID still lives, the lock
is younger than `KIT_LEASE_MINUTES` and your own PID is a different one, the tick aborts with
"second instance". The reason: a session was resumed twice; two processes of the same role
worked in parallel, and `owner:<role>` separates roles, not twins.

If the adapter cannot determine the host PID, the lock only warns (`UNKNOWN`) and does not block.

"Lives" means: a **host** process runs under the PID (`adapters/<host>/host-alive.sh`), not merely
some process — PIDs are handed out again. Every tick clears away anchors of dead or reassigned PIDs.
A background session that only inherited the role does not tick (`is-background.sh`).

A role **never** ends its loop itself, not on a warning and not on STOP, and it asks no
question that waits for input. Both halted the whole team while a reference loop was
running (`evals/findings/2026-09-14-lessons-from-the-reference-loop.md`).

## 9. Memory

The chat is the conversation of one sprint. `memory/<role>/` is the memory of a role across
sprints and resets, `memory/_shared/` the knowledge of everybody. The tool is `bin/brain.sh`, the rules
are `memory/README.md`. The tick pulls it back automatically after every reset.

## 9a. No model without work

A tick is bash and `gh`: it costs no tokens. An empty model round costs a whole
context window. That is why the watchdog loop asks before every start:

```bash
bin/tick.sh --signal     # exit 4 = nothing for you, no model start needed
```

Without the flag the exit code stays 0 — humans and existing callers see no new code.

What counts as work: a rejection, your own or a free ticket of your own queue, a
gap in the artefact chain (for whoever picks up `backlog`), a kanban hint (product-owner), a
mention `@<role>` in the chat, a warning or STOP in the budget. What does **not** count as work is a new
chat line without a mention: otherwise every status change wakes the whole team for one line. It is shown
anyway as soon as the role runs for another reason.

Whoever hands a ticket on wakes the roles that pick up the new state: `bin/status.sh` creates
`.role-loop/<role>.wake`. The mark starts no model — it only ends the waiting, and the check is
done by the tick again. If it gets lost, the interval (`KIT_TICK_INTERVAL`, in steps of
`KIT_TICK_POLL`) wakes the role anyway. So nothing ever stands still, and empty rounds cost nothing.

## 10. Token budget and reset

1. **Watchdog, the real number.** `bin/budget.sh` reads the transcripts of the host. From `KIT_WARN_TOKENS`
   on, the role takes no new ticket; from `KIT_STOP_TOKENS` on, `STOP <role>` stands in `budget.md`.
2. **The emergency brake, without a watchdog.** After `KIT_MAX_TICKETS` tickets retirement anyway — even when the
   watchdog fails or the host writes no transcripts.

**Context size** is the largest input state of a **single** turn
(`input_tokens` + `cache_read_input_tokens` + `cache_creation_input_tokens`), **not** the sum.

**What the thresholds compare is the working share**, not the context: context minus the context of
the session's **first** request. That first request is the scaffolding — system prompt, instructions,
tool schemas, listings — which the role neither chose nor can shrink. A role that carries 95 000 tokens
of scaffolding would otherwise be reset at every threshold no matter how sparingly it works. `budget.md`
reports both numbers, and the state follows the working share.

**A per-role exception** comes from `KIT_WARN_TOKENS_<ROLE>` and `KIT_STOP_TOKENS_<ROLE>` in `kit.env`,
the role name in upper case with `-` as `_` (`product-owner` → `KIT_WARN_TOKENS_PRODUCT_OWNER`). Without
an entry the general thresholds apply; an unreadable entry falls back to them rather than to 0.

A reset always at a ticket boundary: `brain.sh handover` → clear the context (**do not compact**).
The host process may live on: the role hangs on the anchor `.pid-roles/<host-pid>`, not on the
context. The next tick recognises the new session id, registers it and shows the handover.

Autonomously that works with `bin/restart-self.sh`. It ends the host process only when (1) a handover
younger than 10 minutes exists and (2) that handover names every sprint ticket with `owner:<role>` as
`#<nr>` — resetting in the middle of a ticket is allowed that way, and the handover then carries state, SHA
and next step. The restart happens on one of two paths:

- **under the watchdog loop** (`adapters/<host>/role-loop.sh`): end the process, the loop starts it again;
- **in zellij without a loop**: open a tab `<role> (loop)` with `role-loop.sh <role> --after <pid>` and
  end the process only once the loop demonstrably runs. The loop waits until no host lives under the
  old PID any more.

If neither path exists, or opening the tab fails, the script ends nothing.

## 11. Device queue and survival

Exclusive devices are never used in parallel: an entry in `simqueue.md`, wait until you are at the top. A
`HOLDS` entry older than 30 minutes is removed by the watchdog.

If the account limit comes close, **every** session pauses. No new pick-ups. The watchdog
reports it and releases only when the limit has been reset.
