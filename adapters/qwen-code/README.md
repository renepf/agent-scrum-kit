# Adapter: qwen-code

Host: Qwen Code 0.23.4 (Apache-2.0), `~/.nvm/versions/node/v22.21.1/bin/qwen`, needs Node ≥ 22.
Model: a local OpenAI-compatible endpoint, `KIT_LOCAL_BASE_URL` and `KIT_LOCAL_MODEL` in `kit.env`.
Measured 2026-09-15 on an Apple M2 Pro, 32 GiB, Ollama 0.34.0, in `env -i` with its own `QWEN_HOME`.

## 1. Choose the model

```bash
bin/local-model-check.sh
```

Only a model with `tool calls: yes` can run `bin/*.sh`. `start.sh` refuses any other. On the build machine
the only installed model, `qwen2.5-coder:14b`, returned every tool call as JSON text: `tool calls: no`.
Everything below that needs a tool call is therefore **not measured**.

## 2. Start a session

```bash
adapters/qwen-code/start.sh engineer-a
```

`start.sh` checks the model, exports `KIT_ROLE`, `KIT_HOST=qwen-code`, `KIT_HOST_PID` and a fresh
`KIT_SESSION_ID`, changes to `KIT_WORKTREE_ROOT` and replaces itself with:

```
qwen --auth-type openai --model <KIT_LOCAL_MODEL> --openai-api-key local --openai-base-url <KIT_LOCAL_BASE_URL> \
     --session-id <KIT_SESSION_ID> -i "<round prompt from roles/START-HERE.md with the role file>"
```

Measured: these flags alone reach the local model; nothing is written to `~/.qwen/settings.json`. A run with
`QWEN_HOME` pointing at a directory without `settings.json` prints a warning box and works.

## 3. Role file and continuous operation

The first prompt is the host-neutral round prompt with the role file. Measured in an empty project
directory: qwen showed `Read context files: ../qwen-home/output-language.md`, a file it had created in
`QWEN_HOME`. Whether it reads `AGENTS.md` by itself:
`UNKNOWN — start a session in the kit root and look for AGENTS.md under "Read context files"`.
A repeating round (like `/loop` in claude-code): `UNKNOWN — no loop command measured for qwen 0.23.4`.
Until then one start is one round.

## 4. Session id, host PID, end

| What | Measured | Not measured |
|---|---|---|
| session id | `--session-id <uuid>` names the chat file and the registry record `$QWEN_HOME/sessions/<pid>.json` | a shell tool sees `KIT_SESSION_ID`; the id after a context reset |
| processes | three `node` processes: start process, child, grandchild; the registry names the grandchild | — |
| host PID | `start.sh` uses `exec`, so `KIT_HOST_PID` is the start process | a shell tool sees `KIT_HOST_PID` |
| alive | `host-alive.sh` matches `…/bin/qwen ` in the command line; the process name is only `node` | — |
| end | SIGTERM to the start process: no process left after 8 s; the registry file stays | — |
| second call | every prompt also runs `managed-auto-memory-extractor`, a model call of its own (10 883 input tokens after a 20 228-token prompt) | how to switch it off |

## 5. Token budget

`transcript-path.sh <id>` prints `$QWEN_HOME/projects/<cwd with / as ->/chats/<id>.jsonl` (`QWEN_HOME`
default `~/.qwen`). `bin/budget.sh` reads `usageMetadata.promptTokenCount`, which already contains the cached
tokens. `QWEN_RUNTIME_DIR` is documented to move conversations: not measured, not read.

Context mismatch: qwen records `contextWindowSize: 262144` and shows "262.1k Context", while Ollama served
32 768. qwen's own prompt alone was 20 228 tokens. `KIT_WARN_TOKENS` and `KIT_STOP_TOKENS` must sit below the
served context; what Ollama does past it: `UNKNOWN — not measured`.
