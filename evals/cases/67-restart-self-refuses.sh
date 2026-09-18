#!/usr/bin/env bash
CASE_DESC="restart-self.sh ends nothing without a fresh handover, without a restart path, or with a held ticket the handover does not name; in the middle of a ticket, with the ticket named, it works"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap 'kill "$VICTIM" 2>/dev/null; sandbox_cleanup' EXIT
sandbox_sprint > /dev/null
sleep 300 & VICTIM=$!
export KIT_ROLE=engineer-a KIT_HOST_PID="$VICTIM"
unset ZELLIJ_SESSION_NAME KIT_ROLE_LOOP
rs() { "$BIN/restart-self.sh" "$@" 2>&1; }
errors=""
o1="$(rs curiosity)"; case "$o1" in *"reason missing"*) ;; *) errors="$errors reason" ;; esac
o2="$(rs stop)";    case "$o2" in *"no handover"*) ;; *) errors="$errors no-handover" ;; esac
"$BIN/brain.sh" handover "state 2026-09-15" <<<'No ticket open.' > /dev/null
H="$(ls "$SANDBOX/memory/engineer-a/handover/"*.md)"
touch -t "$(date -v-30M '+%Y%m%d%H%M' 2>/dev/null || date -d '-30 min' '+%Y%m%d%H%M')" "$H"
o3="$(rs stop)";    case "$o3" in *"min old"*) ;; *) errors="$errors old-handover" ;; esac
touch "$H"
o4="$(rs stop)";    case "$o4" in *"nobody would start it again"*) ;; *) errors="$errors without-a-restart-path:'$o4'" ;; esac
export KIT_ROLE_LOOP=1
sandbox_issue 7 '{"labels":["sprint:current","status:in-progress","owner:engineer-a"]}'
o5="$(rs stop)";    case "$o5" in *"you hold #7"*"does not name it"*) ;; *) errors="$errors held-not-named:'$o5'" ;; esac
kill -0 "$VICTIM" 2>/dev/null || errors="$errors process-ended-despite-the-rejection"
# #70 in the handover must not count as #7.
sleep 1; "$BIN/brain.sh" handover "state 2026-09-15 in the middle of the ticket" <<<'#70 is another ticket.' > /dev/null
o6="$(rs stop)";    case "$o6" in *"you hold #7"*) ;; *) errors="$errors 70-counted-as-7:'$o6'" ;; esac
sleep 1; "$BIN/brain.sh" handover "state 2026-09-15 in the middle of the ticket" <<<'#7 in-progress, SHA 1a2b3c4d, next step: a test for boundary value 0.' > /dev/null
o7="$(KIT_RESTART_DRY_RUN=1 rs stop)"; case "$o7" in *"DRY RUN"*"held: 7"*"watchdog loop"*) ;; *) errors="$errors middle-of-ticket-rejected:'$o7'" ;; esac
kill -0 "$VICTIM" 2>/dev/null || errors="$errors dry-run-ended-it"
observe "the reason, a missing handover, an old one, no restart path, #7 not named, #70 instead of #7 → 6 rejections, the process lives · #7 named → '$(echo "$o7" | head -1)'${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
