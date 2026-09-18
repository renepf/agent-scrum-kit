🇬🇧 English · [🇩🇪 Deutsch](README.de.md)

# Adapters — how a session starts on your host

The job descriptions under `roles/` are plain Markdown and know no host. An
adapter settles exactly three things:

1. **how a session is started**
2. **how it loads a role file**
3. **how the session id is obtained for the watchdog**

Nothing more belongs in it. If an adapter cannot do without one of those and the owner's
knowledge does not supply it, it says `UNKNOWN — <where to clear it>`. An invented start command is the
worst mistake this repo can make.

| Adapter | State |
|---|---|
| `claude-code` | complete: session id, host PID and transcripts measured 2026-09-10 |
| `cursor` | start attested (`cursor-agent --help`); session id, host PID, transcripts UNKNOWN |
| `codex` | start command UNKNOWN — not installed, not checked |
| `qwen-code` | start, session file, processes, end and transcripts measured 2026-09-15 against a local model; everything that needs a tool call is not measured, because no local model on the build machine produced one |
| `pi` | same state as `qwen-code`: measured 2026-09-15 against a local model, tool-call paths not measured |
| `hermes` | UNKNOWN — ask the owner for the start command, the session id and the tool names |

Every adapter delivers two mandatory executable files:

- `session-id.sh` — prints the session id on stdout, or fails with an exit code ≠ 0.
  **Failing is allowed. Guessing is not.**
- `host-pid.sh` — prints the PID of this session's host process, for the twin lock.
  If it fails, the lock only warns (`UNKNOWN`) and does not block.

Optional, only where the adapter knows it:

- `host-alive.sh <pid>` — exit 0 only when a **host** process lives under that PID. Without this file
  `kill -0` applies, and a reassigned PID of a foreign process counts as a living role.
- `is-background.sh` — exit 0 when the session is a background session that only inherited the role.
  Then the start hook stays silent and `bin/tick.sh` ends with exit 3.
- `start.sh <role>` — starts a session for a role (`qwen-code`, `pi`). Both refuse to start unless
  `bin/local-model-check.sh` passes for `KIT_LOCAL_MODEL`, and export `KIT_SESSION_ID` and `KIT_HOST_PID`
  before they replace themselves with the host.
- `transcript-path.sh <session-id>` — prints the paths of the transcripts, one per line.
  If the host writes no transcripts, the file is not executable or fails —
  then `budget.md` records `UNKNOWN` and the role falls back to the emergency brake
  (retirement after `KIT_MAX_TICKETS` tickets).
