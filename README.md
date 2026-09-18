🇬🇧 English · [🇩🇪 Deutsch](README.de.md)

# agent-scrum-kit

An agent scrum team as a template: nine roles, nine parallel sessions, one ticket per
session, **no subagent**. Copyable into any project, runnable on several LLM hosts.
The commands below apply to the host `claude-code`; for other hosts see
`adapters/<host>/README.md`.

## Short version

```bash
cd <your-project> && git clone https://github.com/renepf/agent-scrum-kit && cd agent-scrum-kit
cp kit.env.example kit.env                  # 1. enter the repo, the paths, the board
bin/board-setup.sh && bin/board-check.sh --write   # 2. set up board + labels, check the mapping
bin/preflight.sh && evals/run.sh --gh       # 3. everything must be green
export KIT_ROLE=product-owner && claude -n product-owner --settings adapters/claude-code/settings.json --mcp-config .mcp.json   # 4. one role per terminal
# 5. first input:  Read roles/_COMMON.md and roles/product-owner.md and take over the role product-owner.
# 6. second input: /loop 10m Run bin/tick.sh. If nothing is waiting for you, end the round. Otherwise work
#                  your role per roles/product-owner.md. No subagent.   (interval per role: table 2.3)
```

The long version follows.

---

## 1. One-time setup

### 1.1 Put the kit into the project and configure it

The kit stays a **folder of its own** inside the project. Never copy its content into the project: the
kit brings its own `README.md`, `AGENTS.md`, `CLAUDE.md`, `.gitignore` and `.git`, and would
overwrite the project's.

```bash
cd <your-project>
git clone https://github.com/renepf/agent-scrum-kit
echo "agent-scrum-kit/" >> .gitignore      # the kit has a history of its own
cd agent-scrum-kit
cp kit.env.example kit.env
```

Fill in at least this much in `kit.env`:

| Key | What belongs in it |
|---|---|
| `KIT_REPO` | the repo with the tickets, `<org>/<repo>` |
| `KIT_WORKTREE_ROOT` | absolute path of the project the engineers create their worktrees in |
| `KIT_BASE_BRANCH` | the integration branch nobody works on directly |
| `KIT_HOST` | `claude-code`, as long as the other adapters carry `UNKNOWN` |

Everything else has a default. `kit.env` is gitignored.

### 1.2 Set up the board and the labels

With a board, the status field of the GitHub Project is the truth and the label only a mirror;
`bin/status.sh` writes both, the board first, and reads the board value back. The long
instructions with every special case are in `INSTALL.md`, step 3.

```bash
gh project create --owner <login-or-org> --title "<project> Scrum"   # the URL contains the number
# in kit.env: KIT_BOARD="github-project", KIT_PROJECT_OWNER, KIT_PROJECT_NUMBER
bin/board-setup.sh           # 8 status options, the link to KIT_REPO, all labels
bin/board-check.sh --write   # 23 check points; board.env appears only when all are OK
```

Without a board: leave `KIT_BOARD="none"` and run only `bin/board-setup.sh --labels-only`.

### 1.3 Check

```bash
bin/preflight.sh      # must print "preflight ok"
evals/run.sh --gh     # must print "failed 0"; --gh checks your real board
```

If `preflight.sh` fails with `Requires authentication`, the token is dead: re-authenticate.
If it says `missing required scopes`, the token is valid and only a permission is missing.

---

## 2. Starting the team

### 2.1 Order

1. **product-owner** and **simplicity-reviewer** first. Before `planned` the PO needs the
   verdict on the solution path, and only their `bin/sprint-new.sh` creates the sprint.
2. **watchdog** right after. It measures from the start and is the only role that commits.
3. Everybody else in any order. They need no special case: their tick reports
   "no active sprint" and ends normally. As soon as the sprint is there, the next tick
   registers them by itself.

### 2.2 Every terminal the same

```bash
cd <your-project>/agent-scrum-kit
export KIT_ROLE=<role>
claude
```

The session starts **in the kit folder**. Only there do the paths `bin/…`, `roles/…` and
`sprints/…` from the role sheets hold. Claude Code then loads the kit's `CLAUDE.md`, that is the
working contract, and the project's `CLAUDE.md` one level up. The engineers still work in the
project: in worktrees under `KIT_WORKTREE_ROOT`.

`KIT_ROLE` must be set **before** `claude` starts. A running session does not see a
variable set later.

Then **two inputs**, one after the other. The first reads the role once:

```
Read roles/_COMMON.md and roles/<file> and take over the role <role>.
Then run bin/tick.sh and work from what it shows you.
One ticket at a time. Never spawn a subagent.
```

The second holds the role in continuous operation. Every round starts with the tick; the
role sheets are **not** read again every round, that would burn context:

```
/loop <interval> Run bin/tick.sh. If nothing is waiting for you, end the round. Otherwise work your role per roles/<file>: one ticket at a time, picking up means setting the In status immediately, no subagent.
```

Every role runs on a **fixed interval** (table 2.3). A round without work ends after the
tick; it costs one tick, no more.

### 2.3 The nine terminals

| # | `KIT_ROLE` | `<file>` | `<interval>` | waits for |
|---|---|---|---|---|
| 1 | `product-owner` | `product-owner.md` | `10m` | sees every state |
| 2 | `simplicity-reviewer` | `simplicity-reviewer.md` | `5m` | `@simplicity-reviewer` from the PO, then `rfr` |
| 3 | `watchdog` | `watchdog.md` | `5m` | nothing, measures on its interval |
| 4 | `engineer-a` | `engineer.md` | `5m` | rejections, then `planned` |
| 5 | `engineer-b` | `engineer.md` | `5m` | rejections, then `planned` |
| 6 | `qa-ruthless` | `qa-ruthless.md` | `5m` | `rfr`, `in-review` |
| 7 | `security-engineer` | `security-engineer.md` | `5m` | `rfr`, `in-review` |
| 8 | `acceptance-tester` | `acceptance-tester.md` | `10m` | `rft` |
| 9 | `merge-gate` | `merge-gate.md` | `10m` | `in-testing` and `@merge-gate` |

Why these cadences: `protocols/LOOP.md` section 4. `engineer-a` and `engineer-b` read the same
sheet; the role name in the first input tells them apart.

The **watchdog** additionally reads the budget rules in its first input:

```
Read roles/_COMMON.md, roles/watchdog.md and protocols/LOOP.md sections 8 and 10
and take over the role watchdog. You read no production code and comment on no
issues. Run bin/tick.sh, then a first round of bin/budget.sh.
Never spawn a subagent.
```

```
/loop 5m Run bin/tick.sh, then a watchdog round per roles/watchdog.md: budget.sh, four looks, commit.sh.
```

The **kit-maintainer** does not run along. You start it only when a case lies in `evals/findings/`
or `evals/run.sh` reports a case as `FAIL` — see `evals/README.md`.

### 2.4 Cutting the first sprint

The product-owner does that themselves, per their role sheet:

1. Write the stories into the tickets — solution-free, plain language, one story per result, one line
   per criterion `AC-<n>: <observable result>`.
2. Per ticket the ledger `tickets/<nr>/GATES.md`: one gate per AC (`protocols/LOOP.md`, gate ledger).
3. `bin/sprint-new.sh <slug> <ticket numbers…>` — the tickets stay on `backlog` while you do this.
   Only this step creates the chat; before it, every `say.sh` fails with
   `no active sprint`.
4. Put the solution path into the chat as a question to `@simplicity-reviewer`, wait for the verdict.
5. Per ticket `bin/status.sh <nr> planned "verdict: <short>"`. Without a gate for every AC it refuses.

At the end of every ticket the product-owner has the last word: `bin/merge.sh <nr>` merges only
once `MERGE-GATE OK` for the current HEAD stands in the PR and CI is green, measured fresh.

From here you need to hand nothing on. A status change puts the ticket into the
queue of the next role; `@<role>` in the chat reaches them at their next tick.

---

## 3. In operation

### 3.1 How you see that it runs

```bash
S=sprints/$(cat sprints/CURRENT)
cat $S/roster.md          # who is registered, with which session id
tail -20 $S/INDEX.md      # what was last in the chat, with file:line
cat $S/budget.md          # context state per role, any STOP lines
KIT_ROLE=product-owner bin/tick.sh   # the PO's situation, without disturbing a session
```

If a role is missing from `roster.md`, it is not ticking. If the watchdog reports a role as silent
for 45 minutes, its session is hanging.

### 3.2 When a session is at its limit

`budget.md` records `STOP <role>`, and that role's tick shows it. At the next
ticket boundary it writes its handover with `bin/brain.sh handover` and one line with `bin/say.sh`.
After that there are two paths; both are measured (2026-09-14, a clean environment):

**`/clear` in the running session.** The process stays, the session id changes. The
SessionStart hook wakes the session without any input; it reads its role sheet, `bin/tick.sh`
registers the new id and shows the handover, and the `/loop` runs on (the session found it
through `CronList` and created no second one). The role comes from the anchor `.pid-roles/<pid>`, the
new session id from `~/.claude/sessions/<pid>.json`. **Not `/compact`** — compacting loses the
technical details the next round hangs on.

**Without a human, through `bin/restart-self.sh stop`.** The role writes its handover (younger than 10 min);
if it still holds tickets, the handover names every `#<nr>` with state, SHA and next step — a
restart in the middle of a ticket is allowed (case 67). If it runs under `adapters/claude-code/role-loop.sh`,
it ends itself and the loop starts `claude` fresh. If it runs without a loop in zellij, the script
opens a tab `<role> (loop)` with `role-loop.sh <role> --after <pid>` and ends itself only once
the loop runs; the loop waits for the end of the old session (case 59, measured with a faked zellij,
not in a real one). Measured with a real `claude` (case 77, 2026-09-14): the role wrote its handover
and called `restart-self.sh stop`, the old process ended after 62 s (`rc=143`), the loop started
`claude` again, and 18 s later the role stood in the roster with a new PID and a new session id — without
any input. The trust dialog appears only at the very first start in the folder, not at a restart.

Independently of the watchdog, every role retires this way after `KIT_MAX_TICKETS` tickets anyway.

### 3.3 When the tick reports "second instance"

The same role already runs in another process — typically after a second `--resume`
of the same session. End the **new** session, not the old one. The lock releases the role
as soon as the old process has ended or has not ticked for `KIT_LEASE_MINUTES`.

### 3.4 When a role sheet or a script changes

Scripts under `bin/` take effect at the next call — all sessions share one
file system. A **role sheet**, by contrast, every running session still holds in its old version
in context. Send the affected session one line before it works on:

```
roles/<file> has changed. Read <section> again before you pick up your next
ticket. Then carry on as before: bin/tick.sh every round.
```

If `roles/_COMMON.md` changes, that concerns all nine sessions.

---

## What lies where

| Place | Content |
|---|---|
| `AGENTS.md` | the working contract. `CLAUDE.md` and `.cursorrules` point at it |
| `roles/` | nine job descriptions plus `kit-maintainer`, plain Markdown, without host vocabulary |
| `INSTALL.md` | setup step by step, with measured outputs and an error table |
| `protocols/LOOP.md` | status model, edges, gates, loop order, tick, chat, twin lock, budget |
| `adapters/<host>/` | how a session starts, loads a role, reports its id |
| `bin/` | `tick.sh`, `status.sh`, `claim.sh`, `merge.sh`, `say.sh`, `reindex.sh`, `brain.sh`, `budget.sh`, `register.sh`, `restart-self.sh`, `sprint-new.sh`, `commit.sh`, `board-setup.sh`, `board-check.sh`, `preflight.sh`, `tickets.sh`, `gates.py`, `gates.sh`, `revise.sh` |
| `tickets/<nr>/` | `GATES.md`: the gate ledger per ticket, one gate per AC, `OWNS:` as the scope, format and rules from unlazy (MIT); the approval of the scope stands as a comment on the issue |
| `evals/` | the suite that checks whether all of this holds |
| `memory/` | memory per role plus a shared one, one file per fact, a generated index |
| `.mcp.json` | the MCP servers context7 and graphify, both through `caveman-shrink`; jcodemunch on opt-in under `adapters/claude-code/mcp/` |
| `kit.env` | **all project knowledge.** No script knows your project, only this file |

## The three rules that carry everything

1. **No subagent.** A role is one session in the main thread. Concurrency comes
   from parallel sessions, never from inside one.
2. **The index is generated.** Chat files are append-only so that line references stay
   valid. `INDEX.md` is always rebuilt and replaced atomically.
3. **Only one role commits.** All sessions share one file system and see each other
   at once; git is only history. Nine parallel rebases would be the only real
   source of conflict.

## Host support

| Host | State |
|---|---|
| `claude-code` | complete, the live evals run against it |
| `cursor` | start attested, session id and transcripts `UNKNOWN` |
| `codex` | start command `UNKNOWN` — not checked |
| `qwen-code`, `pi` | start, session file, processes and transcripts measured against a local model; tool-call paths not measured |
| `hermes` | `UNKNOWN — ask the owner` |

If an adapter lacks a detail, it says `UNKNOWN`. An invented start command would be the
worst mistake this repo can make.

## Licence

MIT, see `LICENSE`.
