🇬🇧 English · [🇩🇪 Deutsch](INSTALL.de.md)

# Installation

From an empty machine to the first tick. Every command here was run on 2026-09-10 against
`renepf/agent-scrum-kit` and the board `renepf/projects/5`, unless it carries the note
**unchecked**.

## 0. Prerequisites

| Tool | What for | Check |
|---|---|---|
| `bash`, `python3` | every script under `bin/` and `evals/` | `bash --version`, `python3 --version` |
| `git` | history, only the watchdog commits | `git --version` |
| `gh` (GitHub CLI), authenticated | tickets, PRs, board | `gh api user -q .login` prints your login |
| a host from `adapters/` | the sessions themselves | `adapters/<host>/README.md` |

The `gh` token needs the scopes `repo` and `project`; `read:org` when the board belongs to an
organisation. Check and add:

```bash
gh auth status | grep -i scopes
gh auth refresh --scopes project          # only when 'project' is missing — unchecked (the token had the scope; only --help was read)
```

**Two different faults, two different fixes.** `Requires authentication` or HTTP 401
means: the token is dead or absent → re-authenticate. `missing required scopes` means: the token is valid,
a permission is missing → add only the scope. `bin/preflight.sh` tells them apart.

## 1. Put the kit into the project

The kit stays a **folder of its own with a history of its own** inside the project. Never copy its content
into the project: it brings its own `README.md`, `AGENTS.md`, `CLAUDE.md`, `.gitignore` and `.git`. The
watchdog commits the sprint state and the memory into the history of the **kit**, never into the project.

```bash
cd <your-project>
git clone https://github.com/renepf/agent-scrum-kit.git
echo "agent-scrum-kit/" >> .gitignore      # unchecked: standard git, not measured
cd agent-scrum-kit
```

Every session later starts **in this folder**. Only there do the paths `bin/…`, `roles/…`
and `sprints/…` hold. The engineers still work in the project, in worktrees under `KIT_WORKTREE_ROOT`.

If you do not want to take the kit's history with you: `rm -rf .git && git init`, then a remote of your
own (**unchecked**, standard git).

## 2. Configuration

```bash
cp kit.env.example kit.env
```

Mandatory in `kit.env`:

| Key | Example | Meaning |
|---|---|---|
| `KIT_REPO` | `my-org/my-project` | repo with tickets and PRs |
| `KIT_WORKTREE_ROOT` | `$HOME/Developer/my-project` | worktree of the project |
| `KIT_BASE_BRANCH` | `development` | integration branch |
| `KIT_HOST` | `claude-code` | adapter under `adapters/` |

Everything else has sensible values. `kit.env` is gitignored. While `KIT_REPO` says `UNKNOWN`,
every script aborts.

Hosts `qwen-code` and `pi` run against a local model. Set `KIT_LOCAL_BASE_URL` to the runtime's
OpenAI-compatible endpoint, then measure what this machine can serve:

```bash
bin/local-model-check.sh    # one line per model: tool calls yes/no/UNKNOWN, memory and context (Ollama)
```

Name a model with `tool calls: yes` as `KIT_LOCAL_MODEL`. A role needs tool calls to run `bin/*.sh`;
the check refuses any other model and picks none for you.

```bash
bin/preflight.sh            # expects: preflight ok · gh · <login> · <repo>
```

## 3. Set up the project board

The status field of the GitHub Project is the truth, the label only a mirror.

**Without a board:** leave `KIT_BOARD="none"`, run only `bin/board-setup.sh --labels-only` and
carry on at step 4. The status then lives in the label alone.

### 3.1 A new board

```bash
gh project create --owner <login-or-org> --title "<project name> Scrum"
```

The output contains the URL `…/projects/<number>`. In `kit.env`:

```bash
KIT_BOARD="github-project"
KIT_PROJECT_OWNER="<login-or-org>"
KIT_PROJECT_NUMBER="<number>"
```

### 3.2 Status options, link, labels

A new project has only `Todo · In Progress · Done` as its status (measured). `board-setup.sh`
replaces the options with the eight from `KIT_STATUS_MAP`, links the project to `KIT_REPO` and
creates every label:

```bash
bin/board-setup.sh
```

Expected output, shortened:

```
status options: Backlog → Planned → In progress → RfR → In review → RfT → In Testing → Done
linked to my-org/my-project
label status:backlog
…
label sprint:current
```

**Caution:** replacing the options deletes the status of every ticket already lying on the
board. That is why the script aborts as soon as the board has entries.

### 3.3 An existing board with tickets

Not `--force`. Instead:

1. Name and sort the options of the status field in the board UI the way `KIT_STATUS_MAP`
   demands — or adapt the **board names** in `KIT_STATUS_MAP` to your board. The keys
   (`backlog`, `planned`, …) stay unchanged, they are protocol.
2. Create only the labels:

```bash
bin/board-setup.sh --labels-only
```

### 3.4 Check that the board mirrors the status model

```bash
bin/board-check.sh --write
```

The check covers 23 points: each of the eight options with its exact name, no surplus option,
the order, seven `status:` labels, six `owner:` labels, the sprint label. Only when all are OK
does it write the IDs into `board.env` (generated, gitignored). Measured on 2026-09-10:

```
OK    board option Backlog               backlog → 6d109d41
…
OK    order                              board: Backlog → Planned → In progress → RfR → In review → RfT → In Testing → Done
…
board-check: all check points OK — renepf/projects/5 mirrors the status model.
board.env written: 10 IDs
```

| FAIL line | Meaning | Fix |
|---|---|---|
| `board option <name> · missing` | the loop cannot set this status | create the option in the board or adapt the name in `KIT_STATUS_MAP` |
| `board option <name> · surplus` | the board shows a status the loop never sets | remove the option (for example `Todo`) |
| `order` | the columns do not follow the forward edge | reorder the options in the board |
| `label <name> · missing in the repo` | `status.sh` cannot set the mirror or the ownership | `bin/board-setup.sh --labels-only` |

If somebody later changes the options of the board, their IDs change. Then run
`bin/board-check.sh --write` again.

## 3a. MCP servers and plugin

The kit ships two MCP servers by default and one on opt-in. Each runs through the proxy
`caveman-shrink@0.1.0`, which shortens the tool descriptions. Prerequisites: `npx` (Node) and `uvx` (uv).

| File | Server | Default |
|---|---|---|
| `.mcp.json` | context7, graphify | on |
| `adapters/claude-code/mcp/jcodemunch.json` | jcodemunch | **off** — a non-commercial licence only, see `adapters/claude-code/README.md` section 5 |

Check that every server starts and answers (this downloads the packages):

```bash
evals/run.sh --net --case 93-mcp-handshake
```

graphify needs a graph under `graphify-out/graph.json` in the kit folder. Without it the
server starts but finds nothing. Build the project's graph:

```bash
uvx --from 'graphifyy[mcp]==0.9.57' graphify update "$KIT_WORKTREE_ROOT"   # unchecked with this path; only 'graphify update .' was measured
```

The caveman plugin (hooks and skills, no MCP) is optional:

```bash
claude plugin marketplace add JuliusBrussee/caveman     # unchecked: only --help was read
claude plugin install caveman@caveman                    # unchecked: only --help was read
```

## 4. Evals

```bash
evals/run.sh                # static cases, no network, no model
evals/run.sh --gh           # plus: your board against the status model (reads only)
evals/run.sh --live         # plus: real model calls against claude-code (costs tokens)
evals/run.sh --net          # plus: MCP handshakes, downloads npm and PyPI packages
```

Exit code 0 = everything green, 1 = a real failure, 2 = blocked (host or GitHub unreachable,
quota exhausted — no verdict about the kit).

## 5. Start the team

`roles/START-HERE.md`: order, intervals, prompt. The host-specific command for
continuous operation is in `adapters/<host>/README.md`.

Every session starts with the hook settings and the MCP configuration:

```bash
cd <your-project>/agent-scrum-kit
export KIT_ROLE=<role>
claude -n "$KIT_ROLE" --settings adapters/claude-code/settings.json --mcp-config .mcp.json
```

At the **very first** start in this folder, claude asks whether you trust it. The preselection is
`No, exit` — choose `Yes, I trust this folder`. Only after that do the hooks run, and only after that
does a role under `adapters/claude-code/role-loop.sh` restart without a human.

Once by hand, before the loops run:

```bash
export KIT_ROLE=product-owner
bin/tick.sh                 # expects: no active sprint … Nothing to do.
```

## 6. When something does not run

| Message | Cause | Fix |
|---|---|---|
| `kit.env is missing` | step 2 is missing | `cp kit.env.example kit.env` |
| `KIT_ROLE is not set` | a terminal without a role | `export KIT_ROLE=<role>` |
| `no session id` | the adapter does not know the id | set `KIT_SESSION_ID` by hand, see the adapter |
| `second instance of '<role>'` | the same role already runs in another process | end the new session, not the old one |
| `no board option for '<status>' in board.env` | step 3.4 is missing or the board changed | `bin/board-check.sh --write` |
| `the board shows '…' for #<nr> instead of '…'` | the board write did not arrive | try again; the label was deliberately left unchanged |
| `planned rejected — no ledger` or `AC without a gate` | the ticket has no checkable contract | one line `AC-<n>:` per AC in the issue, one gate per AC in `tickets/<nr>/GATES.md` |
| `… and #<nr> overlap` | two tickets of the sprint claim the same paths | narrow OWNS in the ledger, or move the ticket to a later sprint |
| `rfr rejected — files outside OWNS` | the PR changes more than the ticket may | take the file out of the PR, or the product-owner approves a new revision with `bin/revise.sh <nr> "<globs>" "<reason>"` |
| `gates.py <command>: … Permission denied: '…/GATES.md.tmp'` or `…/GATES.md: not valid UTF-8 at byte <n>` | the ledger directory is not writable, or the ledger contains bytes that are not UTF-8 | make `tickets/<nr>/` writable for the session; save the ledger as UTF-8 |
| `HANDOFF REQUIRED: AC-<n> (<reason>)` | an AC was given up with `ABANDON` | the product-owner decides: create a follow-up ticket and take the AC out of issue and ledger, or send the ticket back |
| `ERROR AC-<n> [<rule>]` from the lint | a gate measures nothing that can fail | rewrite the gate so the command measures the result itself and prints a line only success knows |
| `the QA PASS for HEAD <sha8> names no mutation for: AC-<n>` | QA named no mutation for this gate | qa-ruthless adds to the PR `QA PASS — HEAD \`<sha8>\`` with a line `AC-<n>: mutation <what> → red` |
| `gates not green for HEAD <sha8>: AC-<n> (…)` | a gate did not run for this HEAD, is red, its definition changed, or a manual gate has no evidence | in the worktree on the HEAD of the PR run `bin/gates.sh run <nr>`; manual: `bin/gates.sh attest <nr> <gate> "<evidence>"` |
| `the worktree is on <sha8>, the PR on <sha8>` | the gates would run against a different state | check out the HEAD of the PR |
| `KIT_LOCAL_MODEL=<model>: refused — tool calls: no (answer came back as text)` | the model writes the tool call as text instead of calling the tool; a role on it cannot run any kit script | pick another model from `bin/local-model-check.sh` with `tool calls: yes` |
| `rft rejected — … missing for HEAD` | a verdict is missing or belongs to an old HEAD | a verdict for the current HEAD in the PR |
