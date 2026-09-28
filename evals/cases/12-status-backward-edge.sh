#!/usr/bin/env bash
CASE_DESC="the backward edge out of in-review and in-testing: back to the original engineer, the full loop again"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

errors=""; finding=""; n0=200
# engineer-a builds, engineer-b reviews and is therefore the one who can throw it back.
for fall in "in-review:engineer-b" "in-testing:engineer-b"; do
  pz="${fall%%:*}"; reviewer="${fall##*:}"; n=$((n0 += 1))
  # One PR number per ticket — two tickets on the same PR would lend each other their verdicts.
  sandbox_issue "$n" "{\"pr\":{\"number\":$n,\"head\":\"feedbeef00\",\"comments\":[],\"checks\":\"pass\"}}"
  sandbox_plannable "$n"
  KIT_ROLE=product-owner "$BIN/status.sh" "$n" planned x > /dev/null 2>&1
  KIT_ROLE=engineer-a "$BIN/status.sh" "$n" in-progress x > /dev/null 2>&1
  KIT_ROLE=engineer-a "$BIN/status.sh" "$n" rfr x > /dev/null 2>&1
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" in-review x > /dev/null 2>&1
  if [ "$pz" = "in-testing" ]; then
    for v in "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment "$n" "$v — HEAD \`feedbeef\` · engineer-b"; done
    sandbox_gates_green "$n" "" engineer-b
    KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rft x > /dev/null 2>&1
    KIT_ROLE=engineer-b "$BIN/status.sh" "$n" in-testing x > /dev/null 2>&1
  fi
  KIT_ROLE="$reviewer" "$BIN/status.sh" "$n" in-progress "fault found" > /dev/null 2>&1 || { errors="$errors $pz:back-refused"; continue; }
  after_back="$(sandbox_labels "$n")"
  case "$after_back" in *"owner:engineer-a"*"status:in-progress"*) ;; *) errors="$errors $pz:owner='$after_back'" ;; esac
  # the same loop again, without a shortcut — and the shortcut itself must fail
  KIT_ROLE=engineer-a "$BIN/status.sh" "$n" rft x > /dev/null 2>&1 && errors="$errors $pz:shortcut-rft-let-through"
  KIT_ROLE=engineer-a "$BIN/status.sh" "$n" rfr again > /dev/null 2>&1 || errors="$errors $pz:reloop-rfr"
  # A third engineer reviews the second round. Which engineer counts as the builder is derived from
  # the comment history (ticket_builder), and the rejection comment was written by engineer-b — so
  # engineer-c is the only reviewer that passes under either reading of that history.
  KIT_ROLE=engineer-c "$BIN/status.sh" "$n" in-review again > /dev/null 2>&1 || errors="$errors $pz:reloop-in-review"
  finding="$finding ${pz} → in-progress (owner:engineer-a) → rfr → in-review;"
done
observe "$finding${errors:+ ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
