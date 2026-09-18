# Long-term memory

One file per fact, with frontmatter. One folder per role, plus a shared one. Every folder has a
**generated** `INDEX.md` with one line per entry — never write it by hand. Tool:
`bin/brain.sh`. The tick pulls the memory back automatically after every reset.

```
memory/
├── _shared/INDEX.md            GENERATED — swarm knowledge
├── _shared/facts/<slug>.md     shared fact; only the author changes or deletes it
└── <role>/
    ├── INDEX.md                GENERATED — handovers, facts, documents, journal, open links
    ├── log.md                  append-only journal
    ├── facts/<slug>.md         one fact per file
    ├── docs/<slug>.md          working notes per ticket, overwritable
    └── handover/<time>.md      handover before every reset
```

## Format of a fact

```markdown
---
name: <slug>
description: <one line — recall is decided on it>
type: user | feedback | project | reference
author: <role>
updated: <YYYY-MM-DD HH:MM>
---

<the fact. For feedback and project, follow with **Why:** and **How to apply:**.>
Related facts as [[their-slug]].
```

`brain.sh` writes the frontmatter itself. `[[slug]]` points at the `name:` field of another
fact. A link without a target is not an error: the index lists it under "Open links" — it
marks a fact that still ought to be written.

| Type | What belongs in it |
|---|---|
| `user` | who the human is: role, expertise, preferences |
| `feedback` | how the work should be done — corrections and confirmed ways, with the reason |
| `project` | ongoing work, goals, constraints that do not follow from the code |
| `reference` | pointers outwards: URLs, dashboards, tickets |

## Rules — `brain.sh` enforces the first three

1. **Check for duplicates before writing.** A new slug with the same description as an
   existing fact is rejected. Rewriting the same slug is the way to change a fact.
2. **Rewrite relative dates as absolute ones.** "yesterday", "last week", "today" are
   rejected. "2026-09-02" is still right in three months.
3. **Only the four types** `user | feedback | project | reference`.
4. **Delete facts that turned wrong, do not amend them:** `brain.sh forget <slug>`, or write the same
   slug again with the right content. A revoked and a valid fact on the same
   subject are worse than none.
5. **Store nothing the repo records anyway:** code structure, fixed faults,
   git history, the content of `AGENTS.md`.
6. Store nothing that holds only for this one conversation.
7. A fact describes the state when it was written. If it names a file, a function or a
   flag, the reading session checks whether it still exists.

## Commands

```bash
TYPE=feedback bin/brain.sh note <slug> "<description>" <<'EOF'   # your own fact
…
EOF
bin/brain.sh share <slug> "<description>" <<'EOF' … EOF          # a fact for everybody
bin/brain.sh forget <slug> [--shared]                             # it turned wrong
bin/brain.sh handover "<description>" <<'EOF' … EOF               # before every reset
bin/brain.sh log "#<nr> · <subject>" <<'EOF' … EOF                # journal
bin/brain.sh recall                                               # after a reset (the tick does it)
```
