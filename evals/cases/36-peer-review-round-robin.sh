#!/usr/bin/env bash
CASE_DESC="four eyes in round robin: an engineer never reviews its own ticket, and every verdict names its reviewer"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

# The builder is the engineer who last set the ticket to in-progress. It stands in the comments
# this script writes itself — the same source the backward edge already uses.
BUILT='{"comments":["**In progress** — engineer-a picked it up"]}'

errors=""

# --- 1. in-review: the builder is turned away, another engineer is let in -----------------
sandbox_issue 5 '{"labels":["status:rfr","owner:engineer-a"],"pr":{"number":50,"head":"11111111aaaa","comments":[],"files":["src/eval.py"]}}'
sandbox_issue 5 "$BUILT"
o1="$(KIT_ROLE=engineer-a "$BIN/status.sh" 5 in-review x 2>&1)"
case "$o1" in *"built"*|*"own"*) ;; *) errors="$errors builder-reviews-itself:'$(printf '%s' "$o1" | tail -1)'" ;; esac

o2="$(KIT_ROLE=engineer-b "$BIN/status.sh" 5 in-review x 2>&1)"
case "$o2" in *"rfr → in-review"*) ;; *) errors="$errors foreign-reviewer-rejected:'$(printf '%s' "$o2" | tail -1)'" ;; esac

# --- 2. rft: the builder may not release, and the verdict must name its reviewer ----------
sandbox_issue 6 '{"labels":["status:in-review","owner:engineer-b"],"pr":{"number":60,"head":"22222222bbbb","comments":[],"files":["src/eval.py"]}}'
sandbox_issue 6 "$BUILT"
sandbox_plannable 6 > /dev/null
sandbox_gates_green 6

rft_as() { KIT_ROLE="$1" "$BIN/status.sh" 6 rft x 2>&1; }

o3="$(rft_as engineer-a)"
case "$o3" in *"built"*|*"own"*) ;; *) errors="$errors builder-releases-itself:'$(printf '%s' "$o3" | tail -1)'" ;; esac

# Verdicts without a reviewer name: rejected, and the message shows the format.
for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment 6 "$v — HEAD \`22222222\`, checked"; done
o4="$(rft_as engineer-b)"
case "$o4" in *"·"*) ;; *) errors="$errors verdict-without-reviewer-accepted:'$(printf '%s' "$o4" | tail -1)'" ;; esac

# A verdict signed by the builder is no second pair of eyes.
sandbox_issue 6 '{"pr":{"number":60,"head":"22222222bbbb","files":["src/eval.py"],"comments":["QA PASS — HEAD `22222222` · engineer-a, eval","SIMPLICITY PASS — HEAD `22222222` · engineer-b, eval","SECURITY PASS — HEAD `22222222` · engineer-b, eval"]}}'
o5="$(rft_as engineer-b)"
case "$o5" in *engineer-a*) ;; *) errors="$errors builders-own-verdict-accepted:'$(printf '%s' "$o5" | tail -1)'" ;; esac

# All three signed by the reviewer: through.
sandbox_issue 6 '{"pr":{"number":60,"head":"22222222bbbb","files":["src/eval.py"],"comments":["SIMPLICITY PASS — HEAD `22222222` · engineer-b, eval","SECURITY PASS — HEAD `22222222` · engineer-b, eval"]}}'
sandbox_gates_green 6
o6="$(rft_as engineer-b)"
case "$o6" in *"in-review → rft"*) ;; *) errors="$errors named-verdicts-rejected:'$(printf '%s' "$o6" | tail -1)'" ;; esac

# --- 3. in-testing: the acceptance runs with the reviewing engineer, not the builder ------
sandbox_issue 7 '{"labels":["status:rft"],"pr":{"number":70,"head":"33333333cccc","comments":[],"files":["src/eval.py"]}}'
sandbox_issue 7 "$BUILT"
o7="$(KIT_ROLE=engineer-a "$BIN/status.sh" 7 in-testing x 2>&1)"
case "$o7" in *"built"*|*"own"*) ;; *) errors="$errors builder-accepts-itself:'$(printf '%s' "$o7" | tail -1)'" ;; esac
o8="$(KIT_ROLE=engineer-c "$BIN/status.sh" 7 in-testing x 2>&1)"
case "$o8" in *"rft → in-testing"*) ;; *) errors="$errors third-engineer-rejected:'$(printf '%s' "$o8" | tail -1)'" ;; esac

# --- 4. done belongs to the product-owner alone -------------------------------------------
sandbox_issue 8 '{"labels":["status:in-testing","owner:engineer-c"],"pr":{"number":80,"head":"44444444dddd","comments":[],"files":["src/eval.py"]}}'
sandbox_plannable 8 > /dev/null
sandbox_gates_green 8 gatesonly
o9="$(KIT_ROLE=engineer-c "$BIN/status.sh" 8 done x 2>&1)"
case "$o9" in *"product-owner"*) ;; *) errors="$errors engineer-sets-done:'$(printf '%s' "$o9" | tail -1)'" ;; esac

# --- 5. the dropped roles are gone, engineer-c exists ------------------------------------
o10="$(KIT_ROLE=qa-ruthless "$BIN/status.sh" 5 in-review x 2>&1)"
case "$o10" in *"unknown role"*) ;; *) errors="$errors dropped-role-still-known:'$(printf '%s' "$o10" | tail -1)'" ;; esac

# --- 6. Round two: a rejection must not turn the reviewer into the builder ----------------
# The comment "**In progress** — <role>" is the only source for who built the ticket. Named it the
# acting role, a rejection would make the rejecting engineer the builder: the real builder could
# review its own work in round two, the rejecting one could not. engineer-c also proves a third
# engineer can be restored as owner at all — the backward edge used to know only a and b.
sandbox_issue 9 '{"labels":["status:in-review","owner:engineer-a"],"pr":{"number":90,"head":"55555555eeee","comments":[],"files":["src/eval.py"]},"comments":["**In progress** — engineer-c picked it up"]}'
o11="$(KIT_ROLE=engineer-a "$BIN/status.sh" 9 in-progress "QA FAIL: back to you" 2>&1)"
case "$o11" in *"owner:engineer-c"*) ;; *) errors="$errors rejection-lost-the-builder:'$(printf '%s' "$o11" | tail -1)'" ;; esac

# The comment of that very transition has to name the builder, not the rejecting engineer.
# The em dash arrives JSON-escaped (\u2014), so match the part that decides the question.
o12="$("$BIN/tickets.sh" comments 9 2>/dev/null | grep -c 'engineer-c (sent back by engineer-a)')"
[ "$o12" -ge 1 ] || errors="$errors comment-names-the-rejector-as-builder"

# Round two: engineer-c is still the builder and may not review; engineer-a may.
sandbox_issue 9 '{"labels":["status:rfr"]}'
o13="$(KIT_ROLE=engineer-c "$BIN/status.sh" 9 in-review "mine again" 2>&1)"
case "$o13" in *"built"*) ;; *) errors="$errors builder-reviews-in-round-two:'$(printf '%s' "$o13" | tail -1)'" ;; esac
o14="$(KIT_ROLE=engineer-a "$BIN/status.sh" 9 in-review "reviewing again" 2>&1)"
case "$o14" in *"rfr → in-review"*) ;; *) errors="$errors rejector-locked-out-in-round-two:'$(printf '%s' "$o14" | tail -1)'" ;; esac

observe "builder in-review/rft/in-testing → rejected · foreign engineer → through · verdict without name → rejected · verdict by the builder → rejected · done only product-owner · qa-ruthless unknown · round two keeps the builder${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
