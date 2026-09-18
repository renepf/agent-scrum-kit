---
role: evals/cases/11-status-illegal-edges.sh
case: 11-status-illegal-edges
date: 2026-09-10
---
Observed: a mutation probe — in `bin/status.sh` the `die "forbidden transition …"` was replaced by
`echo "forbidden transition …"`. The edge lock printed the message but wrote
anyway. Case 11 stayed **green**.

Expected: FAIL. `protocols/LOOP.md` demands that a forbidden transition is **refused**,
not merely reported.

Cause: **a wrong eval.** The case checked one axis (the message), not the guaranteed one (the
state stays unchanged). A second version from a parallel session checked only the
exit code and only as the product-owner — there a role lock could have explained the refusal.

Evidence: `evals/run.sh --case 11-status-illegal-edges` under the mutation, 2026-09-10: `PASS`.

Done: both versions merged. All 40 forbidden pairs, each with the role responsible for the
target, two axes: the message AND unchanged labels. Under the same mutation it is now
`FAIL`, unmutated `PASS 40/40`. No role sheet changed.
