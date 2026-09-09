# Adapter: cursor

Teilweise verifiziert am 2026-09-09: `cursor-agent --help` auf dieser Maschine gelesen.

## 1. Session starten

```bash
cd "$KIT_WORKTREE_ROOT"
export KIT_ROLE=engineer-a
export KIT_HOST=cursor
cursor-agent
```

Belegte Schalter aus `cursor-agent --help`:

- `-p, --print` — nicht-interaktiv, mit vollem Werkzeugzugriff
- `--output-format text|json|stream-json`
- `--resume [chatId]`, `--continue` — Sitzung fortsetzen
- `--model <name>`, `--list-models`

## 2. Rollendatei laden

```bash
cursor-agent "Lies roles/engineer.md und uebernimm die Rolle engineer-a."
```

`.cursorrules` im Repo-Wurzelverzeichnis zeigt auf `AGENTS.md`, den Arbeitsvertrag.

## 3. Session-Kennung

`UNKNOWN — cursor-agent kennt eine chatId (--resume [chatId]), aber wo sie abgelegt wird,
ist nicht geprueft. Zu pruefen unter ~/.cursor/ (Kandidaten: chats/, agents/, projects/).`

Bis das geklaert ist: `KIT_SESSION_ID` von Hand setzen.

## 4. Tokenbudget

`UNKNOWN — Format und Ort der Transkripte nicht geprueft.` `transcript-path.sh` scheitert
deshalb bewusst. Folge: `budget.md` traegt `UNKNOWN` ein, und die Rolle faellt auf die
Notbremse zurueck — Ruhestand nach `KIT_MAX_TICKETS` Tickets.
