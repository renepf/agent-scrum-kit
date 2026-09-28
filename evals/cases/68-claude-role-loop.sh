#!/usr/bin/env bash
CASE_DESC="the watchdog loop: restarts, ends on a stop file, gives up after 3 fast aborts, starts no twin"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$LEBT" 2>/dev/null; rm -rf "$KIT_ROOT/.role-loop" "$KIT_ROOT/.pid-roles/$LEBT"; sandbox_cleanup' EXIT
L="$KIT_ROOT/adapters/claude-code/role-loop.sh"; ST="$KIT_ROOT/.role-loop"
errors=""
rm -rf "$ST"
# A: three fast aborts → the loop gives up, exit 1
KIT_LOOP_CLAUDE='true' KIT_LOOP_SLEEP=0 "$L" engineer-b > /dev/null 2>&1; ra=$?
starts="$(grep -c 'starting claude' "$ST/engineer-b.log")"
[ "$ra" = 1 ] && [ "$starts" = 3 ] || errors="$errors A:rc=$ra,starts=$starts"
# B: a stop file after the second start → the loop ends cleanly
cnt="$SANDBOX/cnt"; : > "$cnt"
KIT_LOOP_CLAUDE="echo x >> '$cnt'; [ \$(wc -l < '$cnt') -ge 2 ] && touch '$ST/engineer-c.stop'; true" KIT_LOOP_SLEEP=0 "$L" engineer-c > /dev/null 2>&1; rb=$?
[ "$rb" = 0 ] && [ "$(wc -l < "$cnt" | tr -d ' ')" = 2 ] || errors="$errors B:rc=$rb,starts=$(wc -l < "$cnt")"
grep -q 'stop file found' "$ST/engineer-c.log" || errors="$errors B:log"
# C: the environment inside the loop: KIT_ROLE and KIT_ROLE_LOOP
envf="$SANDBOX/env"
KIT_LOOP_CLAUDE="echo \"\$KIT_ROLE \$KIT_ROLE_LOOP\" > '$envf'; touch '$ST/watchdog.stop'" KIT_LOOP_SLEEP=0 "$L" watchdog > /dev/null 2>&1
[ "$(cat "$envf")" = "watchdog 1" ] || errors="$errors C:env='$(cat "$envf")'"
# D: a living anchor of the same role → no second start
sleep 300 & LEBT=$!; mkdir -p "$KIT_ROOT/.pid-roles"; echo engineer-a > "$KIT_ROOT/.pid-roles/$LEBT"
od="$(KIT_LOOP_CLAUDE='echo STARTED' "$L" engineer-a 2>&1)"; rd=$?
[ "$rd" != 0 ] && case "$od" in *"is already running"*) true ;; *) false ;; esac || errors="$errors D:'$od'"
case "$od" in *STARTED*) errors="$errors D:twin-started" ;; esac
observe "A: 3 starts, exit $ra · B: stopped after 2 starts, exit $rb · C: the environment '$(cat "$envf")' · D: the twin refused (exit $rd)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
