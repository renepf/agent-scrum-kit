🇬🇧 English · [🇩🇪 Deutsch](README.de.md)

# Evals

```bash
evals/run.sh                 # every case without a model call, free
evals/run.sh --live          # plus the cases with a real model call
evals/run.sh --gh            # plus the cases with real GitHub access (read only)
evals/run.sh --net           # plus the cases with package downloads (MCP handshakes)
evals/run.sh --case <name>   # exactly one case
evals/run.sh --list          # list, execute nothing
```

Every case prints its verdict **with the observed value**. A case that runs only on a
particular host is marked `[host-bound: <host>]`.

| Verdict | Meaning | Exit code of the suite |
|---|---|---|
| `PASS` | passed | |
| `FAIL` | failed | 1 |
| `BLOCK` | the host could not answer: quota exhausted, API error, empty answer | 2 |
| `SKIP` | a live case without `--live`, a gh case without `--gh`, a net case without `--net` | |

`BLOCK` is **not** a verdict about the role. A failed call is a failure,
not a result — the suite derives no state from it, it says "run it again".

## The families

| Prefix | Family | What it checks |
|---|---|---|
| `10–17` | status transitions | the full loop backlog → done through `merge.sh`; all 40 forbidden edges refused, the state unchanged; the backward edge out of `in-review` and `in-testing` back to the original engineer; `owner:` ownership, `rfr`/`rft` ownerless; the `rft` gate: three PASS for the current HEAD; a refused transition writes nothing; the product-owner has the last word, CI measured fresh; board before label, with a read-back |
| `18` | gate ledger | `planned` only with a ledger that covers every AC of the issue and starts fresh; a missing or broken ledger, an unknown AC, a ticked gate, an `ABANDON` up front and an issue without an AC are refused, with a byte comparison of the issue and `tickets/<nr>/`; ten AC spellings including a code fence and an HTML comment |
| `19` | scope | `planned` demands `OWNS:` and records it as revision 1 on the issue; `rfr` refuses a PR file outside it, the old path of a rename included; a self-made OWNS extension and someone else's approval line do not count; six invalid revisions; revision 2 only by the product-owner; without a PR, with two PRs, with an empty or unreadable file list there is no hand-off; 14 glob forms; the gh path through a faked gh |
| `20–24` | concurrency and index | N sessions write at the same time; no entry is lost, the index is complete, deterministic, never half readable, free of sub-headings and valid for an empty sprint too |
| `25–29` | tick | without a sprint it waits; registration once and again after a reset; every foreign entry exactly once, even within the same minute; `@role` reaches exactly that role exactly once; every role sees only its own queue |
| `3x` | budget | known transcripts give exactly the expected context value; the thresholds fire at the right place; missing data gives `UNKNOWN`, never 0 |
| `35` | no model without work | `bin/tick.sh --signal` reports with exit 4 that nothing is waiting, without the flag it stays 0; the watchdog loop then starts no model; a status change wakes exactly the roles that pick up the new state; a wake mark without work starts nothing |
| `34` | budget per host | qwen-code (`usageMetadata.promptTokenCount`, cache included) and pi (`input + cacheRead + cacheWrite`) transcripts give the exact context value, the largest turn and not the sum; a transcript without a usage record the kit knows is `UNKNOWN`, never 0 |
| `4x` | role fidelity (static) | every job description carries the iron rule verbatim, has the same structure, knows no host vocabulary and no project knowledge; a fresh copy runs; never end your own loop and never ask a blocking question — in the sheet, in the tick text and in the hook (45) |
| `54` | local host transcripts | the qwen-code and pi adapters print exactly the transcript of the given session id (paths measured against qwen 0.23.4 and pi 0.85.1), never the newest file of another session, and fail for an unknown id |
| `58` | local model check | against a stub endpoint: a structured tool call is `yes`, a call written as text is `no`, a failed request and an unreachable endpoint are `UNKNOWN`; exit 0 only when `KIT_LOCAL_MODEL` is set and passed |
| `59` | restart without a loop | the zellij path: a tab with `role-loop.sh --after`, ending only once the loop runs, the loop waiting for the end; if the tab fails, nothing is ended |
| `46` | artefact chain | `planned` refuses while `tickets/<nr>/intent.md`, `spec.md` or `plan.md` is missing or empty, names the missing link individually and writes nothing on a rejection; the `requirements-engineer` is in the cast and picks up `backlog` |
| `47` | planning signals | `sprint-new.sh` refuses a ticket without a complete artefact chain and creates nothing; the tick shows the `requirements-engineer` the gaps in the `backlog` with the missing files, and the `product-owner` the kanban numbers including the planning stop, other roles neither |
| `48` | reference finding | with `KIT_REFERENCE_CMD` set, `planned` refuses a `spec.md` without a `REFERENCE:` line and writes nothing; with the line it passes; without a configured reference the kit demands nothing; the role sheet names both keys and its own session |
| `49` | local host start | `adapters/qwen-code/start.sh` and `adapters/pi/start.sh` against fake hosts and a stub endpoint: a model without tool calls starts nothing; a passing model execs the host with the measured flags, the same PID and a fresh session id; pi also needs its `kit-local` provider pointing at the endpoint; `session-id.sh` and `host-pid.sh` print the start values or fail; `host-alive.sh` tells the host from another process |
| `79` | local hosts live (`--live`) | with the model from `kit.env` passing `bin/local-model-check.sh`, qwen-code and pi each run a shell command that sees `KIT_SESSION_ID`, and both transcripts are found; otherwise `BLOCK` |
| `5x` | anti-hallucination (static) | unsettled adapters carry `UNKNOWN`; a failed call changes no state; the session id is never guessed; if the board call fails or the board shows nothing afterwards, label, comment and chat stay unchanged; a reassigned PID does not count as a role (56); a background session with an inherited role does not tick (57) |
| `6x` | loop and context reset | rejections before new tickets; the twin lock; a new session pulls the handover back; the role survives a reset through the anchor on the host process; the SessionStart hook stays silent without a role and wakes only on startup/clear/resume; the session id comes from the registry first; `restart-self.sh` ends nothing without a loop, a fresh handover and the ticket boundary; the watchdog loop restarts, stops, gives up, starts no twin; nine simultaneous registrations give nine roster lines |
| `7x` | live | a real model call: the adapter loads a role, no subagent, a rejection outside the assignment, `UNKNOWN` instead of invention, no "finished" without a measurement; nine sessions start in parallel (75); the role survives `/clear` (76); a real self restart under `role-loop.sh` (77); an interactive role asks no blocking question when something is unclear (78, a behaviour observation without a mutation probe) |
| `8x` | memory | the index is generated, one line per entry, open `[[links]]` visible; a duplicate, a relative date, a wrong type are refused; wrong facts deleted; shared facts changed only by their author |
| `94` | no overlap | `planned`, `revise.sh` and `sprint-new.sh` refuse OWNS that overlap an approved ticket of the same sprint; 11 glob pairs; another sprint and a missing approval do not count; no sprint on a rejection; the gh path with unreadable comments |
| `95` | green for the HEAD | `rft` only once every executable gate ran green for the current HEAD (a real run in a git sandbox); a new push, a wrong checkout and a changed definition invalidate the evidence; exit 0 without EXPECT, EXPECT with exit 1 and a timeout are red; the merge demands evidence for manual gates, only from the acceptance-tester, only for manual gates. Needs a git identity in `~/.gitconfig` |
| `96` | gate lint | 14 rule cases (a fixed output command, a weak EXPECT in German too, a path as a regex, a copied number, hints); `planned` refuses a blind oracle without write access and writes hints into the comment; `rft` refuses a CHECK weakened after planned; `rft` demands one QA mutation line per executable gate for the current HEAD |
| `97` | omission visible | a gate with `ABANDON` blocks `merge.sh` (product-owner and merge-gate) and `done` with `HANDOFF REQUIRED`, the PR stays open, nothing is written; `rft` and `gates.py run` skip the gate; after the product-owner's decision the merge goes through |
| `98` | gate I/O errors | an unwritable ledger (`run`, `attest`) and a ledger that is not valid UTF-8 (`planned`, `lint`, `unmet`, `abandoned`, `qa-lines`) end in one error line naming the file, exit 1, no stack trace; `status.sh planned` refuses and writes nothing |
| `99` | merge report | `planned` records every gate definition as `GATES Revision 1`; `merge.sh` prints each AC of the issue once with its ledger state and the diff's files, before any rejection; a failed read of comments, issue text or file list is `UNKNOWN`; a CHECK changed after planned and an AC without a gate are shown and do not block the merge; a ticket without a GATES line is reported as such |
| `90` | board check | missing, surplus and wrongly ordered options and missing labels are detected; `board.env` appears only on success |
| `91` | board live (`--gh`) | the configured GitHub Project mirrors the status model |
| `92` | MCP configuration | valid JSON, every version pinned exactly, every server through `caveman-shrink`, jcodemunch only on opt-in, the licence note present |
| `93` | MCP live (`--net`) | every shipped server answers `initialize` and `tools/list` |

The live family measures "no subagent" not by the text but by `subagent_stats.spawned`
from the host's result. A declaration of intent in the answer text does not count.

## The closed circle

1. If a role fails an eval, or its work is rejected in practice,
   the **watchdog** writes the case to `evals/findings/`.
2. The **kit-maintainer** turns that into a **pull request** on the job description, with the
   failed case as evidence.
3. A **human** merges. A role never changes its own job description.

Every change to a job description must make at least one previously failed case pass,
without breaking an existing one. Both runs belong in the PR text:

```bash
evals/run.sh --case <the-case>   # FAIL before, PASS after
evals/run.sh                     # no existing case breaks
```

Three answers to a failed case are possible, and all three are allowed:
a missing rule, an ambiguous rule — or **a wrong eval**. An example of the
third lies in `evals/findings/`.

## Adding a case

A file `evals/cases/<nn>-<name>.sh` with three header lines:

```bash
CASE_DESC="what the case checks"
CASE_KIND="static"        # static = free, live = a model call, gh = GitHub access, net = package downloads
CASE_HOST=""              # empty = host-independent, otherwise the host name
```

Then `source ../lib/harness.sh`, `sandbox` for a throwaway environment, at the end
`echo "OBSERVED: $OBSERVED"` and an exit code: 0 passed, anything else failed.
A case checks **only what stands in a job description or in the protocol**. If it demands more,
it is wrong.

**Every new case needs a mutation probe:** switch off the rule it protects in the code →
the case must turn red. A case that stays green with the rule switched off measures the wrong
axis. An example from this repo: case 11 checked only the error message and stayed green when
the edge lock printed the message and wrote anyway.
