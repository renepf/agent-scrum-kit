🇬🇧 English · [🇩🇪 Deutsch](README.de.md)

# Adapter: cursor

Partly verified on 2026-09-09: `cursor-agent --help` read on this machine.

## 1. Start a session

```bash
cd <your-project>/agent-scrum-kit     # in the kit folder, not in the project
export KIT_ROLE=engineer-a
export KIT_HOST=cursor
cursor-agent
```

Attested flags from `cursor-agent --help`:

- `-p, --print` — non-interactive, with full tool access
- `--output-format text|json|stream-json`
- `--resume [chatId]`, `--continue` — continue a session
- `--model <name>`, `--list-models`

## 2. Load a role file

```bash
cursor-agent "Read roles/engineer.md and take over the role engineer-a."
```

`.cursorrules` in the repo root points at `AGENTS.md`, the working contract.

## 3. Session id

`UNKNOWN — cursor-agent knows a chatId (--resume [chatId]), but where it is stored
is not checked. To check under ~/.cursor/ (candidates: chats/, agents/, projects/).`

Until that is settled: set `KIT_SESSION_ID` by hand.

## 4. Token budget

`UNKNOWN — the format and the place of the transcripts are not checked.` `transcript-path.sh`
therefore fails on purpose. The consequence: `budget.md` records `UNKNOWN`, and the role falls back to the
emergency brake — retirement after `KIT_MAX_TICKETS` tickets.
