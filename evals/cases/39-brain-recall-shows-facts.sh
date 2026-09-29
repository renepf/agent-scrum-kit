#!/usr/bin/env bash
CASE_DESC="recall shows the facts, not only a wall of handovers: the handover table is capped and names its total"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
errors=""
B="$BIN/brain.sh"
ME="$SANDBOX/memory/engineer-a"

# A role that has run for a while: 25 handovers, and one fact it must not lose sight of.
printf 'the fact body\n' | KIT_ROLE=engineer-a "$B" note the-one-fact "the fact that matters" > /dev/null 2>&1
# 25 handovers in a row. In the same minute, because a session that resets twice in a minute is
# exactly the case that used to lose one silently.
for i in $(seq -w 1 25); do
  printf 'body %s\n' "$i" | KIT_ROLE=engineer-a "$B" handover "handover number $i" > /dev/null 2>&1
done

files="$(ls "$ME/handover"/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$files" = "25" ] || errors="$errors setup:25-handovers-became-$files"

# 1. The index caps the handover table and says how many there are in total.
rows="$(grep -c '^| \[handover/' "$ME/INDEX.md" || true)"
[ "$rows" -le 20 ] || errors="$errors 1:handover-rows=$rows"
grep -q 'of 25' "$ME/INDEX.md" || errors="$errors 1:total-not-named"

# 2. Nothing is deleted — the index shows fewer, the folder keeps all.
[ "$(ls "$ME/handover"/*.md | wc -l | tr -d ' ')" = "25" ] || errors="$errors 2:files-deleted"

# 3. recall reaches the facts. That is the whole point of an external brain.
out="$(KIT_ROLE=engineer-a "$B" recall 2>&1)"
case "$out" in *"the fact that matters"*) ;; *) errors="$errors 3:fact-missing" ;; esac
case "$out" in *Facts*) ;; *) errors="$errors 3:facts-section-missing" ;; esac

# 4. And the newest handover is still the one recall shows in full.
case "$out" in *"handover number 25"*) ;; *) errors="$errors 4:newest-handover-missing" ;; esac

observe "25 handovers · index rows $rows · recall reaches the fact: $(case "$out" in *"the fact that matters"*) echo yes ;; *) echo no ;; esac)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
