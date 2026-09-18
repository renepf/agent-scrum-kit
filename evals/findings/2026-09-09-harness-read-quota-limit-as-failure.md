---
role: evals/lib/harness.sh
case: 72/73/74-live
date: 2026-09-09
---
Observed: in the acceptance run three live cases failed. The observed value was every time
`You've hit your session limit · resets 6:10pm (Europe/Berlin)` — the host's quota was
exhausted. The suite reported `FAIL` and named the roles as failed.

Expected: no verdict. A failed tool call is a failure, not a result
(`AGENTS.md`, section "The ban on inventing"). The suite derived a state from a failure —
exactly the mistake its own anti-hallucination family forbids.

Cause: **a missing rule in the harness.** `live_claude` passed the host's error message on as
the model's answer, and the evaluation searched it for keywords.

Evidence: `evals/run.sh --live`, run of 2026-09-09 18:0x:
`FAIL 72-live-out-of-scope … answer: You've hit your session limit`

Done: `live_guard` in `evals/lib/harness.sh` recognises quota, API and empty answers
and ends the case with exit code 3. `evals/run.sh` reports that as **BLOCK**, counts it
separately and returns exit code 2 — distinguishable from 1 (a real failure).
Measured with a faked host: `BLOCK 74-live-verification-required … EXIT=2`.
No role sheet changed.
