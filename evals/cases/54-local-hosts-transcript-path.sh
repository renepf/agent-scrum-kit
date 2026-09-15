#!/usr/bin/env bash
CASE_DESC="qwen-code and pi adapters print exactly this session's transcript, never the newest file, and fail for an unknown id"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# Paths measured 2026-09-15 (qwen 0.23.4, pi 0.85.1, env -i, own config dir):
#   qwen  $QWEN_HOME/projects/<cwd with / as ->/chats/<session-id>.jsonl
#   pi    $PI_CODING_AGENT_DIR/sessions/--<cwd with / as ->--/<timestamp>_<session-id>.jsonl
FAKE="$(mktemp -d)"; trap 'rm -rf "$FAKE"' EXIT
Q="$FAKE/qwen"; P="$FAKE/pi"
mkdir -p "$Q/projects/-work-a/chats" "$Q/projects/-work-b/chats" "$P/sessions/--work-a--"
touch "$Q/projects/-work-a/chats/own-qwen.jsonl"
sleep 1; touch "$Q/projects/-work-b/chats/other-qwen.jsonl"       # newest file belongs to another session
touch "$P/sessions/--work-a--/2026-09-15T14-54-01-070Z_own-pi.jsonl"
sleep 1; touch "$P/sessions/--work-a--/2026-09-15T15-00-00-000Z_other-pi.jsonl"

run() { env -i PATH=/usr/bin:/bin HOME="$FAKE/home" "$@"; }
fehler=""
for h in qwen-code pi; do [ -x "$KIT_ROOT/adapters/$h/transcript-path.sh" ] || fehler="$fehler $h:transcript-path.sh-not-executable"; done

qo="$(run QWEN_HOME="$Q" "$KIT_ROOT/adapters/qwen-code/transcript-path.sh" own-qwen 2>/dev/null)"; qrc=$?
qu="$(run QWEN_HOME="$Q" "$KIT_ROOT/adapters/qwen-code/transcript-path.sh" nobody 2>/dev/null)"; qurc=$?
po="$(run PI_CODING_AGENT_DIR="$P" "$KIT_ROOT/adapters/pi/transcript-path.sh" own-pi 2>/dev/null)"; prc=$?
pu="$(run PI_CODING_AGENT_DIR="$P" "$KIT_ROOT/adapters/pi/transcript-path.sh" nobody 2>/dev/null)"; purc=$?

[ "$qrc" = 0 ] && [ "$qo" = "$Q/projects/-work-a/chats/own-qwen.jsonl" ] || fehler="$fehler qwen-own='$qo'(exit $qrc)"
[ "$qurc" != 0 ] && [ -z "$qu" ] || fehler="$fehler qwen-unknown='$qu'(exit $qurc)"
[ "$prc" = 0 ] && [ "$po" = "$P/sessions/--work-a--/2026-09-15T14-54-01-070Z_own-pi.jsonl" ] || fehler="$fehler pi-own='$po'(exit $prc)"
[ "$purc" != 0 ] && [ -z "$pu" ] || fehler="$fehler pi-unknown='$pu'(exit $purc)"

observe "qwen own: exit $qrc '${qo#$FAKE/}' · unknown: exit $qurc · pi own: exit $prc '${po#$FAKE/}' · unknown: exit $purc${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
