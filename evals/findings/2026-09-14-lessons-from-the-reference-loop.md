---
role: roles/_COMMON.md, bin/tick.sh, bin/common.sh, adapters/claude-code
case: practice — the reference loop, ported as cases 45, 56, 57, 78
date: 2026-09-14
---
Four rejections out of the real operation of a reference loop with eight roles. The kit had caught
none of them; each is taken over here as a rule or a tool check plus an eval case.

1. **Roles ended their own loop.** On a warning or STOP every role deleted its loop and
   waited for a human. The team stood still for three days.
   Cause: a missing rule. → `_COMMON.md` "Never end your own loop", the tick text on a warning and
   on STOP, the hook text (case 45; mutation of the tick text, the hook line, the rule → red).

2. **A role asked interactively and stood for 299 s**, until a human looked into its terminal.
   Cause: a missing rule. → `_COMMON.md` "Never ask a question that waits for input", the hook text
   (case 45; case 78 live and interactive: no call, no dialog — a behaviour observation, no
   mutation probe possible, because model behaviour without the rule is not deterministic).
   A side finding: in `claude -p` the question tool is not available; a -p case would have measured
   nothing and therefore reported BLOCK instead of PASS.

3. **A role anchor pointed at a reassigned PID** (a foreign system process). `kill -0` held
   it for a running role.
   Cause: a missing check in the tool. → `host_alive` (the adapter knows which process name is a host),
   in the lease, the loop and the anchor clean-up at every tick (case 56; mutation of the clean-up off,
   host_alive = kill -0 → red).

4. **A background session inherited the role** and was woken as a role by the hook.
   Cause: a missing check. → `adapters/claude-code/is-background.sh` (`CLAUDE_CODE_SESSION_KIND=bg`);
   the hook stays silent, the tick ends with exit 3. Explicitly NOT through `CLAUDE_CODE_CHILD_SESSION` — that
   variable stands in every tool environment and would have locked every role (case 57; mutation of the tick
   without the lock, the hook without the lock, the check through CHILD_SESSION → red).
