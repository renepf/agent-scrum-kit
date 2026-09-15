# Adapter: pi

Host: pi coding agent 0.85.1 (MIT), `~/.nvm/versions/node/v22.21.1/bin/pi`, needs Node ≥ 22.19.
Model: a local OpenAI-compatible endpoint, `KIT_LOCAL_BASE_URL` and `KIT_LOCAL_MODEL` in `kit.env`.
Measured 2026-09-15 on an Apple M2 Pro, 32 GiB, Ollama 0.34.0, in `env -i` with its own `PI_CODING_AGENT_DIR`.

## 1. Choose the model

```bash
bin/local-model-check.sh
```

Only a model with `tool calls: yes` can run `bin/*.sh`. `start.sh` refuses any other. On the build machine
the only installed model, `qwen2.5-coder:14b`, answered through pi with the call as text
(`{"name": "bash", "arguments": {"command": "sh probe.sh pi"}}`, `stopReason: stop`): `tool calls: no`.
Everything below that needs a tool call is therefore **not measured**.

## 2. Provider entry

pi reaches a local endpoint only through a provider in `~/.pi/agent/models.json` (`PI_CODING_AGENT_DIR`
moves the directory). The kit does not write that file. `start.sh` checks for this entry and prints it when
it is missing or points elsewhere:

```json
{
  "providers": {
    "kit-local": {
      "baseUrl": "<KIT_LOCAL_BASE_URL>",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [{ "id": "<KIT_LOCAL_MODEL>" }]
    }
  }
}
```

Format from pi `docs/models.md`. Measured: the provider names `ollama` and `kit-local` both reached the model.

## 3. Start a session

```bash
adapters/pi/start.sh engineer-a
```

`start.sh` checks model and provider, exports `KIT_ROLE`, `KIT_HOST=pi`, `KIT_HOST_PID` and a fresh
`KIT_SESSION_ID`, changes to `KIT_WORKTREE_ROOT` and replaces itself with:

```
pi --provider kit-local --model <KIT_LOCAL_MODEL> --session-id <KIT_SESSION_ID> "<round prompt from roles/START-HERE.md with the role file>"
```

Measured traps: `pi -p` (one-shot) waits for end of input on an open stdin, give it `< /dev/null`; the
interactive TUI ends on end of input, so it needs a terminal. pi showed `0.0%/128k (auto)` while Ollama served
32 768 tokens of context.

## 4. Role file and continuous operation

The first message is the host-neutral round prompt with the role file. pi loads `AGENTS.md` and `CLAUDE.md`
unless `--no-context-files` (pi `--help`); that it read the kit's `AGENTS.md`:
`UNKNOWN — not measured in the kit root`. pi also loaded skills from the user's own directories
(`find-skills`, `just-scrape`) although `PI_CODING_AGENT_DIR` pointed elsewhere; `--no-skills` exists, its effect
on a role: not measured. A repeating round: `UNKNOWN — pi has no loop command in --help`; one start is one
round.

## 5. Session id, host PID, end

| What | Measured | Not measured |
|---|---|---|
| session id | `--session-id <uuid>` names the session file `…_<uuid>.jsonl`; pi warns "No project session found … creating a new session with that id" | the bash tool sees `KIT_SESSION_ID`; `PI_SESSION_ID` (pi docs); the id after `/new` |
| processes | one process named `pi` | — |
| host PID | `start.sh` uses `exec`, so `KIT_HOST_PID` is that process | the bash tool sees `KIT_HOST_PID` |
| alive | `host-alive.sh` checks the process name `pi` | — |
| end | SIGTERM to `pi`: no process left after 8 s | — |

## 6. Token budget

`transcript-path.sh <id>` prints `$PI_CODING_AGENT_DIR/sessions/--<cwd with / as ->--/<timestamp>_<id>.jsonl`
(default `~/.pi/agent`). `bin/budget.sh` reads `message.usage.input + cacheRead + cacheWrite`.
`PI_CODING_AGENT_SESSION_DIR` and `--session-dir` are documented to move sessions: not measured, not read.
