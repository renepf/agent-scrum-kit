---
role: bin/register.sh
case: 69-register-nine-parallel (new), found by the start test with nine real sessions
date: 2026-09-14
---
Observed: nine claude sessions started in parallel, each ran `bin/tick.sh` → `register.sh`. Afterwards
`roster.md` had 4 of 9 lines. The anchors (`.pid-roles/`) and the leases were right for all nine.

Expected: nine lines. `bin/budget.sh` reads the roster — a missing role the watchdog never measures.

Cause: **a missing rule in the tool, and a gap in the suite.** `register.sh` held only the
lock per role (`.lease-<role>.lock`), but `roster.md` is shared by every role. Nine
simultaneous read-modify-write runs under nine different locks overwrote each other.
No eval case started several roles at the same time.

Evidence: case 69 against the old code, three runs: `roster.md: 2/9`, `1/9`, `1/9` lines.

Done: a second, shared lock `roster.md.lock`. The first attempt nested both locks and
broke case 62 (the twin lock): `with_lock` sets a clean-up trap, the inner one overwrote the
outer, and a `die` in the twin check then left the lease lock lying around. Now one after the other,
never nested. Case 69 three times 9/9, case 62 green, the mutation (the roster lock removed) → red.
No role sheet changed.
