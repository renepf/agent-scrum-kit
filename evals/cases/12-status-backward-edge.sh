#!/usr/bin/env bash
CASE_DESC="the backward edge out of in-review and in-testing: back to the original engineer, the full loop again"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

errors=""; finding=""; n0=200
for fall in "in-review:qa-ruthless" "in-testing:acceptance-tester"; do
  pz="${fall%%:*}"; reviewer="${fall##*:}"; n=$((n0 += 1))
  # One PR number per ticket — two tickets on the same PR would lend each other their verdicts.
  sandbox_issue "$n" "{\"pr\":{\"number\":$n,\"head\":\"feedbeef00\",\"comments\":[],\"checks\":\"pass\"}}"
  sandbox_plannable "$n"
  KIT_ROLE=product-owner "$BIN/status.sh" "$n" planned x > /dev/null 2>&1
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" in-progress x > /dev/null 2>&1
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rfr x > /dev/null 2>&1
  KIT_ROLE=qa-ruthless "$BIN/status.sh" "$n" in-review x > /dev/null 2>&1
  if [ "$pz" = "in-testing" ]; then
    for v in "QA PASS" "SIMPLICITY PASS" "SECURITY PASS"; do sandbox_pr_comment "$n" "$v — HEAD \`feedbeef\`"; done
    sandbox_gates_green "$n"
    KIT_ROLE=qa-ruthless "$BIN/status.sh" "$n" rft x > /dev/null 2>&1
    KIT_ROLE=acceptance-tester "$BIN/status.sh" "$n" in-testing x > /dev/null 2>&1
  fi
  KIT_ROLE="$reviewer" "$BIN/status.sh" "$n" in-progress "fault found" > /dev/null 2>&1 || { errors="$errors $pz:back-refused"; continue; }
  after_back="$(sandbox_labels "$n")"
  case "$after_back" in *"owner:engineer-b"*"status:in-progress"*) ;; *) errors="$errors $pz:owner='$after_back'" ;; esac
  # the same loop again, without a shortcut — and the shortcut itself must fail
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rft x > /dev/null 2>&1 && errors="$errors $pz:shortcut-rft-let-through"
  KIT_ROLE=engineer-b "$BIN/status.sh" "$n" rfr again > /dev/null 2>&1 || errors="$errors $pz:reloop-rfr"
  KIT_ROLE=security-engineer "$BIN/status.sh" "$n" in-review again > /dev/null 2>&1 || errors="$errors $pz:reloop-in-review"
  finding="$finding ${pz} → in-progress (owner:engineer-b) → rfr → in-review;"
done
observe "$finding${errors:+ ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
