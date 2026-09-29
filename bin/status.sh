#!/usr/bin/env bash
# Change a ticket status — board, label and ownership in one command.
#
#   bin/status.sh 712 in-progress "picked up, worktree open"
#
# An order that closes two real sources of error:
#   0. check EVERYTHING before anything is written: edge, role, ownership, gate.
#      A rejected transition touches neither board nor label.
#   1. board first (the truth). If it fails, the label stays unchanged.
#   2. label as the mirror, owner:<role> as ownership, comment, chat.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

T="$BIN_DIR/tickets.sh"
P="$KIT_LABEL_PREFIX"; O="$KIT_OWNER_PREFIX"
# Four eyes in round robin: every engineer reviews, none reviews what it built. The gate does not
# ask which role you are, it asks whether you are the builder — see ticket_builder in common.sh.
ENGINEERS="engineer-a engineer-b engineer-c"
REVIEWERS="$ENGINEERS"

# The only allowed edges. Two of them are the backward edge.
EDGES="
backlog>planned
planned>in-progress
in-progress>rfr
rfr>in-review
in-review>rft
rft>in-testing
in-testing>done
in-review>in-progress
in-testing>in-progress
"

[ $# -ge 2 ] || die "usage: bin/status.sh <ticket> <status> [comment]"
TICKET="$1"; NEW="$2"; NOTE="${3:-}"
case " $KIT_STATES " in *" $NEW "*) ;; *) die "unknown status '$NEW'. Allowed: $KIT_STATES" ;; esac

R="$(role)"
SID="$(session_id)"
"$BIN_DIR/preflight.sh" > /dev/null || die "preflight failed — stop and report, do not work around it"

in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

LABELS="$("$T" labels "$TICKET")" || die "#$TICKET: labels not readable — a failure, not a state"
OLD="$(printf '%s\n' "$LABELS" | grep "^$P" | head -1 | sed "s|^$P||" || true)"
[ -n "$OLD" ] || OLD="backlog"
OWNERS_NOW="$(printf '%s\n' "$LABELS" | grep "^$O" | sed "s|^$O||" | tr '\n' ' ' || true)"

[ "$OLD" != "$NEW" ] || die "#$TICKET is already on '$NEW' — no transition"
case "$EDGES" in
  *"$OLD>$NEW"*) ;;
  *) die "forbidden transition '$OLD' → '$NEW'. Allowed from '$OLD': $(printf '%s\n' "$EDGES" | grep "^$OLD>" | sed "s|^$OLD>||" | tr '\n' ' ')" ;;
esac

# --- 0. role, ownership, gate — before any write --------------------------------
OWNER=""; KEEP=""; OWNS_LEDGER=""; GATES_LEDGER=""; LINT_MSG=""
case "$NEW" in
  backlog|planned)
    [ "$R" = "product-owner" ] || die "'$NEW' is set only by the product-owner, not $R"
    if [ "$NEW" = "planned" ]; then
      # No code without a checkable contract: every AC of the issue has a gate, the ledger names its scope.
      BODY="$("$T" body "$TICKET")" || die "#$TICKET: issue text not readable — a failure, not a state"
      OWNS_LEDGER="$(printf '%s\n' "$BODY" | python3 "$BIN_DIR/gates.py" planned "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" \
        || die "#$TICKET: planned rejected — $OWNS_LEDGER"
      # The approved definition of every gate: merge.sh reports a CHECK changed after this point.
      GATES_LEDGER="$(python3 "$BIN_DIR/gates.py" definitions "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" \
        || die "#$TICKET: planned rejected — $GATES_LEDGER"
      # No oracle that cannot fall. Hints do not reject, they go into the comment.
      LINT_MSG="$(printf '%s\n' "$BODY" | python3 "$BIN_DIR/gates.py" lint "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" \
        || die "#$TICKET: planned rejected — lint:
$LINT_MSG"
      # Artefact chain per ticket: intent.md (problem and why), spec.md (observable behaviour),
      # plan.md (steps and files). With a link missing the product-owner plans blind; the
      # requirements-engineer supplies it before a ticket enters the sprint.
      for CHAIN in intent.md spec.md plan.md; do
        grep -q '[^[:space:]]' "$TICKETS_DIR/$TICKET/$CHAIN" 2>/dev/null \
          || die "#$TICKET: planned rejected — $CHAIN is missing or empty under $TICKETS_DIR/$TICKET/ (requirements-engineer)"
      done
      # If there is a reference to compare against (KIT_REFERENCE_CMD), the finding belongs in spec.md:
      # one line "REFERENCE: <what was checked, with a time>". Without a configured reference the kit
      # demands nothing — it does not know the project.
      if [ -n "${KIT_REFERENCE_CMD:-}" ]; then
        grep -q '^REFERENCE:' "$TICKETS_DIR/$TICKET/spec.md" 2>/dev/null \
          || die "#$TICKET: planned rejected — spec.md without a REFERENCE line although KIT_REFERENCE_CMD is set (the requirements-engineer checks against the reference and records the finding)"
      fi
      # No overlap: no path that another approved ticket of the sprint already holds.
      CLAIMS="$(sprint_claims "$TICKET")" || exit 1
      OVERLAP="$(printf '#%s\t%s\n%s\n' "$TICKET" "$OWNS_LEDGER" "$CLAIMS" | python3 "$BIN_DIR/gates.py" overlap "#$TICKET" 2>&1)" \
        || die "#$TICKET: planned rejected — $OVERLAP"
    fi
    ;;
  in-progress)
    if [ "$OLD" = "planned" ]; then
      in_list "$R" "$ENGINEERS" || die "out of 'planned' a ticket is picked up only by an engineer, not $R"
      OWNER="$R"
    else
      case "$OLD" in
        in-review)  in_list "$R" "$ENGINEERS product-owner" || die "out of 'in-review' only the reviewing engineer or the product-owner rejects, not $R" ;;
        in-testing) in_list "$R" "$ENGINEERS product-owner" || die "out of 'in-testing' only the reviewing engineer or the product-owner rejects, not $R" ;;
      esac
      # Backward edge: the ticket goes back to the engineer that built it. One source for that,
      # the same the four-eyes gates ask: ticket_builder in common.sh. Its own copy of the regex
      # knew only engineer-a and engineer-b and left a third engineer without an owner.
      OWNER="$(ticket_builder "$TICKET")"
      [ -n "$OWNER" ] || die "#$TICKET: no earlier engineer in the comment history — do not guess"
    fi
    ;;
  rfr)
    in_list "$R" "$ENGINEERS" || die "'rfr' is set only by an engineer, not $R"
    in_list "$R" "$OWNERS_NOW" || die "#$TICKET does not belong to $R (ownership: ${OWNERS_NOW:-nobody})"
    # Scope: every file of the PR lies within the OWNS revision the product-owner approved on the issue.
    COMMENTS="$("$T" comments "$TICKET")" || die "#$TICKET: comments not readable — a failure, not a state"
    APPROVAL="$(printf '%s' "$COMMENTS" | python3 "$BIN_DIR/gates.py" approved 2>&1)" || die "#$TICKET: rfr rejected — $APPROVAL"
    PR_LINE="$("$T" pr "$TICKET" 2>&1)" \
      || die "#$TICKET: rfr rejected — no linked PR readable (closes #$TICKET in the PR text?)${PR_LINE:+: $PR_LINE}"
    FILES="$("$T" pr-files "${PR_LINE%% *}")" || die "PR #${PR_LINE%% *}: file list not readable — a failure, not a state"
    SCOPE_MSG="$(printf '%s\n' "$FILES" | python3 "$BIN_DIR/gates.py" scope "${APPROVAL#*$'\t'}" 2>&1)" \
      || die "#$TICKET: rfr rejected (OWNS revision ${APPROVAL%%$'\t'*}) — $SCOPE_MSG"
    ;;
  in-review)
    in_list "$R" "$REVIEWERS" || die "'in-review' is picked up only by an engineer, not $R"
    BUILDER="$(ticket_builder "$TICKET")"
    [ "$R" != "$BUILDER" ] || die "#$TICKET: in-review rejected — $R built this ticket itself. Four eyes means another engineer reviews: hand it over in the chat."
    OWNER="$R"; KEEP=""
    ;;
  rft)
    in_list "$R" "$REVIEWERS" || die "'rft' is set only by an engineer, not $R"
    BUILDER="$(ticket_builder "$TICKET")"
    [ "$R" != "$BUILDER" ] || die "#$TICKET: rft rejected — $R built this ticket and may not release it itself."
    verdicts_missing "$TICKET" "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"
    [ -z "$VERDICT_MISSING" ] || die "#$TICKET: rft rejected — in PR #$VERDICT_PR the following is missing for HEAD $VERDICT_HEAD8:$VERDICT_MISSING. Format of the first line: '<VERDICT> — HEAD \`$VERDICT_HEAD8\` · <engineer>, ...'"
    # Every verdict names its reviewer. Without the name four eyes cannot be measured: all sessions
    # share one account, and since one role gives all three verdicts, the kind of verdict no longer
    # tells who wrote it.
    while IFS='=' read -r v a; do
      [ -n "$v" ] || continue
      [ -n "$a" ] || die "#$TICKET: rft rejected — '$v' in PR #$VERDICT_PR names no reviewer. First line: '$v — HEAD \`$VERDICT_HEAD8\` · <engineer>, ...'"
      [ "$a" != "$BUILDER" ] || die "#$TICKET: rft rejected — '$v' comes from $a, who built the ticket. Another engineer has to review it."
    done <<VERDICTS
$VERDICT_AUTHORS
VERDICTS
    # The verdicts do not replace the comparison: every executable gate ran green for this HEAD.
    GATE_MSG="$(python3 "$BIN_DIR/gates.py" unmet "$TICKETS_DIR/$TICKET/GATES.md" "$VERDICT_HEAD8" runnable 2>&1)" \
      || die "#$TICKET: rft rejected — $GATE_MSG"
    # A CHECK may have been weakened since planned and run green because of it: the lint runs again.
    BODY="$("$T" body "$TICKET")" || die "#$TICKET: issue text not readable — a failure, not a state"
    LINT_RFT="$(printf '%s\n' "$BODY" | python3 "$BIN_DIR/gates.py" lint "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" \
      || die "#$TICKET: rft rejected — lint:
$LINT_RFT"
    # Per executable gate, QA names the mutation that turns exactly that gate red.
    PR_COMMENTS="$("$T" pr-comments "$VERDICT_PR")" || die "PR #$VERDICT_PR: comments not readable — a failure, not a state"
    QA_MSG="$(printf '%s' "$PR_COMMENTS" | python3 "$BIN_DIR/gates.py" qa-lines "$TICKETS_DIR/$TICKET/GATES.md" "$VERDICT_HEAD8" 2>&1)" \
      || die "#$TICKET: rft rejected — $QA_MSG"
    ;;
  in-testing)
    in_list "$R" "$REVIEWERS" || die "'in-testing' is picked up only by an engineer, not $R"
    BUILDER="$(ticket_builder "$TICKET")"
    [ "$R" != "$BUILDER" ] || die "#$TICKET: in-testing rejected — $R built this ticket. The acceptance is run by another engineer."
    OWNER="$R"
    ;;
  done)
    # Since the cast shrank there is no merge-gate: done and the merge belong to the product-owner.
    case "$R" in
      product-owner) ;;
      *) die "'done' is set only by the product-owner — not $R" ;;
    esac
    # Not even past the merge is there a done while an AC is given up via ABANDON.
    HANDOFF="$(python3 "$BIN_DIR/gates.py" abandoned "$TICKETS_DIR/$TICKET/GATES.md" 2>&1)" || die "#$TICKET: done rejected — $HANDOFF"
    ;;
esac

# --- 1. board first -------------------------------------------------------------
if [ "$KIT_BOARD" = "github-project" ]; then
  KEY="KIT_OPTION_$(echo "$NEW" | tr 'a-z-' 'A-Z_')"
  OPT="${!KEY:-}"
  [ -n "$OPT" ] || die "no board option for '$NEW' in board.env — run bin/board-check.sh --write"
  "$T" board-set "$TICKET" "$OPT" "$(board_name "$NEW")" || die "board status not set — the label stays unchanged on purpose"
fi

# --- 2. label as the mirror -----------------------------------------------------
for l in $(printf '%s\n' "$LABELS" | grep "^$P" || true); do
  "$T" rm-label "$TICKET" "$l"
done
[ "$NEW" = "done" ] || "$T" add-label "$TICKET" "$P$NEW"

# Ownership via owner:<role>. All sessions often share ONE account — the assignee cannot tell
# engineer-a and engineer-b apart, the label can.
for o in $OWNERS_NOW; do
  if [ "$o" = "$OWNER" ] || in_list "$o" "$KEEP"; then continue; fi
  "$T" rm-label "$TICKET" "$O$o"
done
[ -z "$OWNER" ] || in_list "$OWNER" "$OWNERS_NOW" || "$T" add-label "$TICKET" "$O$OWNER"
if [ -z "$OWNER" ]; then
  for a in $("$T" assignees "$TICKET"); do "$T" unassign "$TICKET" "$a"; done
fi

# Who the comment names: at in-progress the OWNER, everywhere else the acting role. Reason: this
# line is the only source for "who built this ticket" (ticket_builder). Named it the actor, a
# rejection would make the reviewer the builder — then the real builder could review its own work
# in the second round and the rejecting one could not (measured 2026-09-29).
WER="$R"
if [ "$NEW" = "in-progress" ] && [ -n "${OWNER:-}" ] && [ "$OWNER" != "$R" ]; then
  WER="$OWNER (sent back by $R)"
fi

# On planned this comment is at the same time the approval of the scope (bin/gates.py approved).
"$T" comment "$TICKET" "**$(board_name "$NEW")** — $WER · $(now) · session \`$SID\`

${NOTE:-_no comment_}${OWNS_LEDGER:+

OWNS Revision 1: \`$OWNS_LEDGER\`}${GATES_LEDGER:+
GATES Revision 1: \`$GATES_LEDGER\`}${LINT_MSG:+

Lint hints:
$LINT_MSG}"

[ "$NEW" != "done" ] || "$T" close "$TICKET"

if [ -f "$CURRENT_FILE" ]; then
  KIT_ROLE="$R" "$BIN_DIR/say.sh" "#$TICKET · $(board_name "$NEW")" <<EOF > /dev/null
${NOTE:-Status change without a comment.}
EOF
fi

# Whoever picks up the new state is woken: otherwise they wait for the next interval although
# the work is already there. If the mark gets lost, the interval wakes them (fallback line).
wake_roles "$NEW"

# The local ticket list follows the board (D50). One board call, so it can happen after every
# transition. This ticket is exempt from the comparison — its row is supposed to have changed.
# A failed rebuild does not undo the transition that already happened: it is reported, not fatal.
"$BIN_DIR/sprint-list.sh" --expect-change "$TICKET" > /dev/null \
  || echo "warning: #$TICKET moved, but the local list could not be rebuilt" >&2

echo "#$TICKET: $OLD → $NEW${OWNER:+ (owner:$OWNER)}"
