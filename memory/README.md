# Langzeitgedaechtnis

Eine Datei je Fakt, mit Frontmatter. Je Rolle ein Ordner, dazu ein geteilter. Jeder Ordner hat einen
**generierten** `INDEX.md` mit einer Zeile je Eintrag — nie von Hand schreiben. Werkzeug:
`bin/brain.sh`. Der Tick holt das Gedaechtnis nach jedem Reset automatisch zurueck.

```
memory/
├── _shared/INDEX.md            GENERIERT — Schwarmwissen
├── _shared/facts/<slug>.md     geteilter Fakt; nur der Autor aendert oder loescht ihn
└── <rolle>/
    ├── INDEX.md                GENERIERT — Uebergaben, Fakten, Dokumente, Journal, offene Verweise
    ├── log.md                  append-only Journal
    ├── facts/<slug>.md         ein Fakt je Datei
    ├── docs/<slug>.md          Arbeitsnotizen je Ticket, ueberschreibbar
    └── handover/<zeit>.md      Uebergabe vor jedem Reset
```

## Format eines Fakts

```markdown
---
name: <slug>
description: <eine Zeile — danach wird beim Erinnern entschieden>
type: user | feedback | project | reference
author: <rolle>
updated: <YYYY-MM-DD HH:MM>
---

<der Fakt. Bei feedback und project danach **Warum:** und **Wie anzuwenden:**.>
Verwandte Fakten als [[ihr-slug]].
```

`brain.sh` schreibt das Frontmatter selbst. `[[slug]]` zeigt auf das `name:`-Feld eines anderen
Fakts. Ein Verweis ohne Ziel ist kein Fehler: der Index listet ihn unter "Offene Verweise" — er
markiert einen Fakt, der noch geschrieben werden sollte.

| Typ | Was hinein gehoert |
|---|---|
| `user` | wer der Mensch ist: Rolle, Fachgebiet, Vorlieben |
| `feedback` | wie gearbeitet werden soll — Korrekturen und bestaetigte Wege, mit Begruendung |
| `project` | laufende Arbeit, Ziele, Randbedingungen, die nicht aus dem Code hervorgehen |
| `reference` | Zeiger nach aussen: URLs, Dashboards, Tickets |

## Regeln — `brain.sh` erzwingt die ersten drei

1. **Vor dem Schreiben auf Dubletten pruefen.** Ein neuer Slug mit derselben Beschreibung wie ein
   vorhandener Fakt wird abgelehnt. Denselben Slug neu zu schreiben ist der Weg, einen Fakt zu aendern.
2. **Relative Datumsangaben in absolute umschreiben.** "gestern", "letzte Woche", "today" werden
   abgelehnt. "2026-09-02" bleibt in drei Monaten richtig.
3. **Nur die vier Typen** `user | feedback | project | reference`.
4. **Falsch gewordene Fakten loeschen, nicht ergaenzen:** `brain.sh forget <slug>`, oder denselben
   Slug mit dem richtigen Inhalt neu schreiben. Ein widerrufener und ein gueltiger Fakt zum selben
   Thema sind schlechter als keiner.
5. **Nichts speichern, was das Repo ohnehin festhaelt:** Codestruktur, behobene Fehler,
   Git-Historie, der Inhalt von `AGENTS.md`.
6. Nichts speichern, was nur fuer dieses eine Gespraech gilt.
7. Ein Fakt beschreibt den Stand beim Schreiben. Nennt er eine Datei, eine Funktion oder einen
   Schalter, prueft die lesende Session, ob es das noch gibt.

## Befehle

```bash
TYPE=feedback bin/brain.sh note <slug> "<beschreibung>" <<'EOF'   # eigener Fakt
…
EOF
bin/brain.sh share <slug> "<beschreibung>" <<'EOF' … EOF          # Fakt fuer alle
bin/brain.sh forget <slug> [--shared]                              # falsch geworden
bin/brain.sh handover "<beschreibung>" <<'EOF' … EOF               # vor jedem Reset
bin/brain.sh log "#<nr> · <betreff>" <<'EOF' … EOF                 # Journal
bin/brain.sh recall                                                # nach Reset (macht der Tick)
```
