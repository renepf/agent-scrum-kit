#!/usr/bin/env bash
CASE_DESC="a new session id in the tick pulls the memory back with the last handover, a known one does not"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
KIT_ROLE=engineer-a KIT_SESSION_ID=alt "$BIN/brain.sh" handover "state before the reset: #12 rfr, SHA 1a2b3c4d" <<'EOF' > /dev/null
Next step: wait for the rejection from qa-ruthless.
EOF
fresh="$(KIT_ROLE=engineer-a KIT_SESSION_ID=fresh "$BIN/tick.sh" 2>&1)"
again="$(KIT_ROLE=engineer-a KIT_SESSION_ID=fresh "$BIN/tick.sh" 2>&1)"
errors=""
printf '%s' "$fresh" | grep -q 'SHA 1a2b3c4d' || errors="$errors handover-not-shown"
printf '%s' "$fresh" | grep -q 'wait for the rejection from qa-ruthless' || errors="$errors body-not-shown"
printf '%s' "$again" | grep -q 'last handover' && errors="$errors recall-on-every-round"
observe "a new session: the handover shown · a second tick of the same session: no recall${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
