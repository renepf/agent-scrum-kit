# agent-scrum-kit

Ein Agenten-Scrum-Team als Vorlage: neun Rollen, neun parallele Sessions, ein Ticket je
Session, **kein Subagent**. Kopierbar in jedes Projekt, lauffaehig auf mehreren LLM-Hosts.

## Team starten — in zehn Zeilen

```bash
git clone <dieses-repo> && cd agent-scrum-kit
cp kit.env.example kit.env      # 1. Repo, Pfade, Schwellen eintragen
bin/preflight.sh                # 2. muss "preflight ok" drucken
evals/run.sh                    # 3. muss gruen sein
export KIT_ROLE=product-owner   # 4. je Terminal eine Rolle (Liste: roles/START-HERE.md)
<start-befehl aus adapters/$KIT_HOST/README.md>
#  5. erster Prompt: "Lies roles/product-owner.md und uebernimm die Rolle."
bin/sprint-new.sh mein-ziel 1 2 3 4 5 6   # 6. der PO schneidet den Sprint
#  7. dann Terminal 2 bis 9 nach roles/START-HERE.md starten
```

## Was wo liegt

| Ordner | Inhalt |
|---|---|
| `AGENTS.md` | der Arbeitsvertrag. `CLAUDE.md` und `.cursorrules` verweisen darauf |
| `roles/` | neun Jobbeschreibungen plus `kit-maintainer`, reines Markdown, ohne Host-Vokabular |
| `protocols/LOOP.md` | Statusmodell, Rueckwaertskante, Chat, Budget, Reset |
| `adapters/<host>/` | wie eine Session startet, eine Rolle laedt, ihre Kennung meldet |
| `bin/` | die Werkzeuge: Status, Chat, Index, Budget, Sprint, Commit |
| `evals/` | die Suite, die prueft, ob das alles haelt |
| `memory/` | dateibasiertes Langzeitgedaechtnis, eine Datei je Fakt |
| `kit.env` | **alles Projektwissen.** Kein Skript kennt dein Projekt, nur diese Datei |

## Die drei Regeln, die alles tragen

1. **Kein Subagent.** Eine Rolle ist eine Session im Haupt-Thread. Nebenlaeufigkeit entsteht
   durch parallele Sessions, nie innerhalb einer.
2. **Der Index ist generiert.** Chatdateien sind append-only, damit Zeilenverweise dauerhaft
   gelten. `INDEX.md` wird immer neu gebaut und atomar ersetzt.
3. **Nur eine Rolle committet.** Alle Sessions teilen ein Dateisystem und sehen einander
   sofort; Git ist nur Historie. Neun parallele Rebases waeren die einzige echte
   Konfliktquelle.

## Host-Unterstuetzung

| Host | Zustand |
|---|---|
| `claude-code` | vollstaendig, Live-Evals laufen dagegen |
| `cursor` | Start belegt, Sessionkennung und Transkripte `UNKNOWN` |
| `codex` | Startbefehl `UNKNOWN` — nicht geprueft |
| `pi` (PI Code, QWEN-Harness) | `UNKNOWN — beim Owner erfragen` |
| `hermes` | `UNKNOWN — beim Owner erfragen` |

Fehlt einem Adapter eine Angabe, steht dort `UNKNOWN`. Ein erfundener Startbefehl waere der
schlimmste Fehler, den dieses Repo machen kann.

## Lizenz

MIT, siehe `LICENSE`.
