# LIBRARIAN — the shared project wiki and its only writer

Design plus first implementation (2026-09-30: `bin/wiki.sh`, hooks, eval cases 100–102). Evidence and German working notes:
the ops repo file `scrum/KV-CACHING-LLM-WIKI-OKF.md` (sections 3–5 measurements, 6 and 10 design).
Every fact below is marked **MEASURED** (own run 2026-09-29), **DOC** (Anthropic docs), **OKF-SPEC**
(v0.2, Google Cloud), **NB** (notebook "Claude Best Principles", a source claim, not proof), or
`UNKNOWN — <where to clear it>`.

## 1. Principle

- The wiki is **shared project knowledge**: one OKF bundle per project, kept in the project's ops repo
  (`WIKI_ROOT`, set in `kit.env`), never in the kit.
- **Exactly one writer: the librarian** (owner decision D62). Roles read files directly and send
  requests (`add`, `update`) to the librarian. Role-private memory (`brain.sh`, `agents/<role>/memory`)
  is unchanged and stays multi-writer.
- The model produces **text only**. Code (`bin/wiki.sh`) reads, writes, links and verifies. A local
  model that returns tool calls as JSON text (kit measurement, `qwen2.5-coder:14b`) is therefore
  usable, and a wrong answer is rejected by the script instead of executed.
- **Nothing from the wiki goes into the prompt prefix.** It reaches a role as a tool result at the
  end of `messages`. See section 6.

## 2. Format: OKF v0.2 profile

Markdown files with YAML frontmatter (OKF-SPEC). Only `type` is required. The profile we add:

| Field | Use |
|---|---|
| `type` | `feature`, `screen`, `service`, `data-model`, `api-contract`, `requirement`, `decision`, `parity-gap`, `question` |
| `sources` | `path:line-line@commit`; the commit is pinned |
| `generated` | `{by, at}` (OKF-SPEC replaces v0.1 `timestamp`) |
| `verified` | list of `{by, at}`; **empty list = unchecked** (our reading of "UNGEPRUEFT"; OKF has no such state) |
| `status` | `draft \| stable \| deprecated` (OKF-SPEC) |
| `stale_after` | ISO-8601 instant (OKF-SPEC); the values per type are a proposal: 30 / 14 / 90 days |
| extension keys | `android_sources`, `parity_status` (proposal; OKF allows extra keys) |

`index.md` (router, under 200 lines, `okf_version: "0.2"` in the root one), `log.md` (newest first,
`YYYY-MM-DD` headings). `UNKNOWN` items are files of `type: question`, never a word in running text.
Superseded facts get `status: deprecated`; nothing is deleted (NB, "close, never delete").

## 3. Interface: `bin/wiki.sh`

| Command | Who | Effect |
|---|---|---|
| `seed` | session-start hook | 10–15 lines: which concepts exist; byte-identical for an identical wiki, **no timestamps** |
| `query "<question>"` | any role | reads `index.md`, then the matching files; answers with concept, `path:line@commit`, `verified` state; says so when `verified` is empty |
| `add` / `update` | any role | a **request**, queued; only the librarian applies it |
| `verify <file>` | librarian, CI | every claim needs a verbatim quote found in its source at the pinned commit; otherwise the claim is rejected (NB, MindBase pattern) |
| `lint` | cron, before sprint end | orphans (not reachable from `index.md`), dead links, `stale_after` passed, unverified older than 14 days; deterministic, no model |
| `scan <scope.json>` | librarian | deterministic first-fill pass, no model: one concept per source file, symbol table with a verbatim declaration quote per symbol |
| `describe <concept>` | librarian | the model proposes one German sentence and one quote per symbol (`id¦text¦quote`); the script keeps a proposal only if the quote is found in the symbol's lines; result goes to staging |
| `fill [prefix]` | librarian | `describe` then `verify --promote` per file, one log line per file, a `.wiki-stop` file halts between batches, resumes at files missing from `log.md` |
| `ask "<question>"` | any role, via the librarian | the local model only names ids (file, then symbol); the script renders `tag:path:a-b@sha` |
| `golden <golden.json>` | librarian, CI | runs the questions through `ask`, scores under the strict rule; the golden file lives outside the wiki |
| `receipt <sid>` / `gate <sid>` | hooks | S3 writes, S2 checks the receipt; the denial names `wiki.sh query` |

Rules the script enforces: enrich before create (patch an existing concept when the fact is an
attribute), link both ways, one source file per log entry, staging directory before promotion.

## 4. Amnesia gates (deterministic, owner decision D60)

A role must not need to remember to look. Three hooks in `adapters/claude-code/`:

1. **S1 seed**: `SessionStart` appends `wiki.sh seed` to the role anchor. Lands in `messages`.
2. **S2 gate**: `PreToolUse` on `Edit`/`Write` under the configured source path denies until the
   session holds a receipt. The denial names `wiki.sh query "<question>"`.
3. **S3 receipt**: `PostToolUse` on `Bash` writes the receipt for `session_id` after a `wiki.sh query`.

MEASURED 2026-09-30: `PreToolUse` fires in a `claude -p` session (fixture project: Write denied, model ran `wiki.sh query`, retry allowed). `UNKNOWN — whether it also fires in a /loop role session (same hook mechanism, not measured there).`
`UNKNOWN — whether roles stall under S2; measure before enabling it on the running team.`
Do not put the seed into an MCP tool description: tool definitions live in `tools`, and any change
there invalidates every later layer (DOC).

## 5. Runtime and model

- `llama-server` from Homebrew `llama.cpp` (0.5.0 available, not installed on the build machine),
  model named in one config file so it can be swapped. `llama-swap` in front is an NB proposal, not tested.
- Approved 2026-09-29: **Qwen3.6-35B-A3B UD-Q4_K_XL, 20.8 GiB** (huggingface.co/unsloth). Gemma-4-26B-A4B
  is **not** approved for download; it is the second candidate for a later comparison (`A2`).
- Fit: 20.8 GiB does not run beside an iOS simulator on 32 GiB. Run it only when simulators are idle.
- Measured reference on the build machine (M2 Pro, 32 GiB, Ollama 0.34.0, `qwen2.5-coder:14b` dense):
  **137.6 tokens/s prompt, 12.0 tokens/s generation**, identical prompt a second time 0.07 s. MEASURED 2026-09-30 for Qwen3.6-35B-A3B UD-Q4_K_XL under llama-server (Metal, 32k context): **521.5 tokens/s prompt, 33.8 tokens/s generation** (5 068-token prompt, identical prompt a second time 103 ms via prompt cache); tool calls: yes (`bin/local-model-check.sh`).
  Dense-14B figures above stay as the reference. The notebook's "2 to 5 hours for 33 MB" confuses generation with prompt rate.
- Swapping the model keeps the wiki (files) and drops KV caches and prompt tricks. A candidate is judged on
  **golden questions**: questions with a known file and line, taken from the 35 code comparisons under
  `scrum/agents/requirements-engineer/docs/*-quervergleich-code.md` in the ops repo. Pass threshold (owner, 2026-09-29):
  **100 %**, and the librarian must reach it **independently**, without a human correcting an answer.
  Counting rule (owner, 2026-09-29, strict): a question counts as answered only when the answer names the
  expected file **and** line range. A partial hit (right file, wrong lines) or an answer without a source is a miss.

## 6. Cache rules (MEASURED, `claude -p`, one prefix, one variable at a time)

| Change | Effect |
|---|---|
| model | nothing read, everything rewritten |
| effort | Sonnet 5.5: `messages` only; Opus 4.8 and Opus 5: `system` and `messages`, `tools` stays |
| git status of the working directory | `messages` only; a directory without git is immune |
| `CLAUDE.md` | `messages` only (in Claude Code; the raw API differs, DOC) |

A wiki change must therefore never touch `CLAUDE.md`, `MEMORY.md` or `roles/`.

## 7. First fill

Sources stay in place and are pinned by commit; nothing is copied into a `raw/` folder.

1. Pilot slice **Auth + Sales** (open tickets #814, #1181, #1182). Full run only after the owner reads the pilot report.
2. Order for the full run: requirements, iOS, Android, ops documents **without** sprint logs.
3. Deterministic pass first (headings, symbols, `path:line`), model second (description, links), `verify` third.
4. Staging, then promotion; an abort resumes at the source missing from `log.md`.
5. Both apps are covered: iOS is the reference, Android exists already (1 060 source files); the wiki holds the **gap**.

Size and time, MEASURED sizes / estimated time for the dense 14B: requirements 3.73 MB, iOS 3.29 MB,
ops without logs 7.41 MB, sprint logs 11.3 MB (excluded). 21–31 h for the three included sets at the
measured 14B speed. Android size and MoE speed: `UNKNOWN`.

## 8. Not decided

`UNKNOWN — schema of android_sources / parity_status` (proposal only) · jcodemunch 1.1.5 ships Swift and Kotlin parser specs (read in its source, **not run** on our files); `UNKNOWN — graphify`; the first fill uses its own regex scan instead ·
`UNKNOWN — Gemma 4 licence and 4-bit size`.
"Gauntlet" = a fixed sequence of pass/fail gates with one goal (owner confirmed the reading, 2026-09-29); the takeover prompt is in the ops handover, section 17.
