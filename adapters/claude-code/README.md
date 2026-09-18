🇬🇧 English · [🇩🇪 Deutsch](README.de.md)

# Adapter: claude-code

Verified on this machine on 2026-09-09.

## 1. Start a session

One terminal per role, all in the same folder:

```bash
cd "$KIT_WORKTREE_ROOT"
export KIT_ROLE=engineer-a
claude
```

## 2. Load the role file and run continuously

The first prompt, verbatim, with the interval and the file from `roles/START-HERE.md`:

```
/loop 5m Run bin/tick.sh. If nothing is waiting for you, end the round. Otherwise work your
role per roles/engineer.md: one ticket at a time, picking up means setting the In status immediately,
no subagent.
```

`/loop` with a fixed interval starts the round even when the role is waiting for nothing.
An empty round ends after the tick.

## 3. Session id, host PID, context reset

- **Host PID:** `host-pid.sh` walks up the process chain to the process `claude`. The PID stays the same
  across every tool call of a session — **and across `/clear`**.
- **Session id:** `session-id.sh` reads `~/.claude/sessions/<host-pid>.json` first (field
  `sessionId`), then `CLAUDE_CODE_SESSION_ID`. Measured 2026-09-14 in a clean environment: after `/clear`
  the registry carries the new id under the same PID. Whether `CLAUDE_CODE_SESSION_ID` changes as well is
  **not measured** in a clean environment. Never derive it from the youngest transcript file.
- **A living host:** `host-alive.sh <pid>` checks the process name `claude`. A PID is handed out again after
  the process ends; an anchor must not then count as a running role. `bin/tick.sh` clears away anchors
  of dead or reassigned PIDs at every tick.
- **Background sessions:** `is-background.sh` recognises `CLAUDE_CODE_SESSION_KIND=bg`. Such sessions
  inherit `KIT_ROLE` but are not a role. Do **not** check `CLAUDE_CODE_CHILD_SESSION`: that variable
  stands in the tool environment of every session (reference measurement 2026-09-14).
- **The role across `/clear`:** `bin/tick.sh` writes `.pid-roles/<host-pid>` at every tick. Without
  `KIT_ROLE`, `bin/common.sh` reads the role there.
- **Start hook:** `settings.json` attaches `session-start.sh` to `SessionStart` twice: once for the
  role anchor as context, once with `--wake` (asyncRewake), which wakes the session after `startup`, `clear`
  and `resume` without any input. Measured: a start without a prompt registers itself; after `/clear` the
  session reads its role again, ticks (a new id in the roster) and finds its running `/loop`.
- **No model without work:** before every start the loop runs `bin/tick.sh --signal`. Exit 4 means
  "nothing for you": it then starts no `claude` but waits up to `KIT_TICK_INTERVAL` seconds in
  steps of `KIT_TICK_POLL` — or less, when a status change creates `.role-loop/<role>.wake`.
- **Watchdog loop:** `role-loop.sh <role> [--after <pid>]` starts `claude -n <role> --settings … --mcp-config
  .mcp.json` and starts it again as soon as it ends. With `--after` it waits up to 120 s until no
  `claude` lives under that PID — that is how `bin/restart-self.sh` opens it in a zellij tab before the old session
  ends. Stopping: `touch .role-loop/<role>.stop`. Measured with a
  faked `claude` (case 68: restart, stop, giving up, twin) and with a real `claude`
  (case 77: a self restart through `restart-self.sh`, a new PID and session id without any input). claude stores
  the trust in the folder in `~/.claude.json` (`hasTrustDialogAccepted`), which is why the restart does
  not hang on the dialog.
- **Mind the crash guard:** if `claude` ends three times in a row after less than 60 s, the loop gives
  up. A role that resets itself again right after being woken counts as a fast
  abort.

**A measuring trap for tests:** whoever starts `claude` from inside a running claude session inherits
`CLAUDE_CODE_CHILD_SESSION=1`, `CLAUDE_PID` and the messaging socket. The started session then wrote
neither the registry nor a transcript in the usual place. So start test sessions with `env -i` and only
`HOME PATH USER LANG TERM KIT_ROLE` (as in cases 75 and 76).

## 4. Recommended settings for Opus 5

Source: the owner's NotebookLM collection ("Claude Best Principles", queried 2026-09-09).
**Not re-measured by me** — I did not check the names of the environment variables in point 3 below
against the Claude Code documentation.

1. **Set the model explicitly**, never rely on defaults: `claude-opus-5`.
2. **Do not switch thinking off.** Switching it off leads to faulty tool calls and
   visible internal tags. Control the cost through the effort level instead:
   `medium` is the working range, `low` for routine, `high` produces overthinking and
   drift.
3. **Lock subagents mechanically** — otherwise the iron rule stands only in the text:
   ```bash
   export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=0
   export CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=0
   ```
   `UNKNOWN — check the names against the Claude Code documentation, the only evidence so far is the
   NotebookLM source.` The eval `no-subagent` checks the behaviour, not the variable.
4. **No `/compact`.** Compacting loses most of the technical details. With a full
   context: write the handover, clear the context, start again. That is how
   `protocols/LOOP.md` section 7 puts it.
5. **No "check your answer again" instructions** in prompts. Opus 5 verifies
   itself; extra demands produce over-verification and cost tokens without
   return. That is why `AGENTS.md` demands a **measurement**, not a re-checking loop.
6. **Keep rule files lean.** Past 300 lines the result measurably worsens.
   `AGENTS.md` deliberately stays below that, the details live in subfolders with a routing table.

## 4a. Dialogs that block an unattended start

Measured on 2026-09-14 against an interactive session in a fresh kit folder:

- **The trust dialog at the first start in a folder.** The preselection is `❯ No, exit` — a
  blind Enter ends claude. Choose `Yes, I trust this folder` by hand once before roles run
  under `role-loop.sh`; otherwise every restart hangs on that dialog. With `-p` it does not
  appear.
- **`/exit` with a running `/loop`.** claude asks `Background work is running … 1. Exit and stop
  tasks / 2. Stay`. Whoever ends a role by hand confirms with `1`. `bin/restart-self.sh`
  is not affected: it ends the process with `kill -TERM`.
- **A start without input.** With `--settings adapters/claude-code/settings.json` the hook
  `session-start.sh --wake` (asyncRewake) wakes the session by itself after the trust dialog: it read
  `roles/_COMMON.md` and `roles/engineer.md`, ran `bin/tick.sh`, registered itself and created
  its 5-minute loop with `CronCreate` — without a single typed prompt.
- In `-p` the same wake hook reports `outcome: error` (exit 2, the anchor text on stderr). The session
  runs through normally regardless; there the context hook delivers the anchor as `additionalContext`.

## 5. MCP servers

The kit ships MCP servers in two files. Each runs through `caveman-shrink@0.1.0` (MIT), a
stdio proxy from the caveman project that shortens the tool descriptions. Every version is pinned
exactly; measured on 2026-09-14 with `initialize` + `tools/list`:

| Server | File | Package | Licence | Tools | Descriptions raw → shortened |
|---|---|---|---|---|---|
| context7 | `.mcp.json` | `@upstash/context7-mcp@4.1.0` (npx) | MIT | 2 | 2435 → 2351 characters |
| graphify | `.mcp.json` | `graphifyy[mcp]==0.9.57` (uvx) | Apache-2.0 | 10 | 1229 → 1187 characters |
| jcodemunch | `adapters/claude-code/mcp/jcodemunch.json` | `jcodemunch-mcp==1.108.318` (uvx) | dual-use, see below | 6 | — |

Prerequisites: `npx` (Node) and `uvx` (uv). graphify reads `graphify-out/graph.json` relative to the
kit folder; without a graph the server still starts (measured). The graph is built by `graphify update <path>`.

`graphifyy` needs the extra `[mcp]`: without it `graphify-mcp` ends with
`ModuleNotFoundError: No module named 'mcp'` (measured against a `uv tool install graphifyy`).

Starting with MCP:

```bash
claude -n "$KIT_ROLE" --settings adapters/claude-code/settings.json --mcp-config .mcp.json
```

### jcodemunch — on opt-in only

`jcodemunch-mcp` is published under the **jCodeMunch-MCP Dual-Use License 1.1**, not under an
open-source licence. Clause 3: the software must not be used "in any product, service, or workflow that
generates revenue, is offered commercially, or is used within a for-profit organization to support
revenue-generating activities". Free is non-commercial use only;
commercial use needs the author's permission (J. Gravelle,
https://github.com/jgravelle/jcodemunch-mcp). The kit distributes no code, only a start command —
whether your use is allowed you must check yourself. That is why it is not in `.mcp.json`.

Switching it on:

```bash
claude … --mcp-config .mcp.json adapters/claude-code/mcp/jcodemunch.json
```

The version the server reports is unreliable (`==1.27.0` reports itself as 1.30.0 with 50 tools);
pinned is 1.108.318, a router version with 6 tools and about 2400 characters of description.

### caveman as a plugin

`caveman` itself is not an MCP server but a plugin of hooks and skills. The commands below
match `claude plugin marketplace add --help` and `claude plugin install --help`; they were not
run on the measuring machine, where the plugin was already installed (**unchecked**):

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```
