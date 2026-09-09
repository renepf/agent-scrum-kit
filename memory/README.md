# Langzeitgedaechtnis

Eine Datei je Fakt. `MEMORY.md` ist der Index — eine Zeile je Eintrag, sonst nichts.
Der Index wird in jede Session geladen; die Einzeldateien nur, wenn eine Zeile passt.

## Format einer Gedaechtnisdatei

```markdown
---
name: <kurzer-kebab-case-slug>
description: <eine Zeile, danach wird beim Erinnern entschieden>
type: user | feedback | project | reference
---

<der Fakt. Bei feedback und project danach **Warum:** und **Wie anzuwenden:**.>
Verwandte Eintraege als [[ihr-name]] verlinken.
```

`[[name]]` zeigt auf das `name:`-Feld eines anderen Eintrags. Ein Verweis, den es noch
nicht gibt, ist kein Fehler — er markiert etwas, das noch geschrieben werden sollte.

## Die vier Typen

| Typ | Was hinein gehoert |
|---|---|
| `user` | wer der Mensch ist: Rolle, Fachgebiet, Vorlieben |
| `feedback` | wie du arbeiten sollst — Korrekturen und bestaetigte Wege, immer mit Begruendung |
| `project` | laufende Arbeit, Ziele, Randbedingungen, die nicht aus dem Code hervorgehen |
| `reference` | Zeiger nach aussen: URLs, Dashboards, Tickets |

## Regeln

- **Vor dem Schreiben auf Dubletten pruefen.** Gibt es eine Datei, die den Fakt schon
  abdeckt, aenderst du sie. Kein zweiter Eintrag zum selben Sachverhalt.
- **Falsch gewordene Eintraege loeschen, nicht ergaenzen.** Ein Gedaechtnis mit einem
  widerrufenen und einem gueltigen Eintrag zum selben Thema ist schlechter als keines.
- **Nichts speichern, was das Repo ohnehin festhaelt:** Codestruktur, behobene Fehler,
  Git-Historie, der Inhalt von `AGENTS.md`.
- **Relative Datumsangaben in absolute umschreiben.** "letzte Woche" ist in drei Monaten
  falsch; "2026-09-02" bleibt richtig.
- Nichts speichern, was nur fuer dieses eine Gespraech gilt.
- Ein Eintrag beschreibt den Stand zum Zeitpunkt des Schreibens. Nennt er eine Datei, eine
  Funktion oder einen Schalter, prueft die lesende Session, ob es das noch gibt.

## Nach dem Schreiben

Eine Zeile in `MEMORY.md` ergaenzen:

```
- [Titel](datei.md) — Aufhaenger in wenigen Woertern
```

Nie den Inhalt selbst in `MEMORY.md`.
