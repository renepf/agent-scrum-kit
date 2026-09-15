#!/usr/bin/env bash
# Starts one interactive qwen-code session for a role against the local model.
#   adapters/qwen-code/start.sh <role>
#
# Refuses to start unless KIT_LOCAL_MODEL passes bin/local-model-check.sh: without tool calls a role cannot run
# bin/*.sh. Endpoint and model go in as CLI flags only (measured 2026-09-15, qwen 0.23.4); nothing is written to
# ~/.qwen. exec keeps this PID, so KIT_HOST_PID is the qwen start process; SIGTERM to that process ended all
# three node processes of a measured session.
source "$(dirname "${BASH_SOURCE[0]}")/../../bin/common.sh"
[ $# -eq 1 ] || die "usage: adapters/qwen-code/start.sh <role>"
case " $KIT_ROLES " in *" $1 "*) ;; *) die "unknown role '$1'. Allowed: $KIT_ROLES" ;; esac
ROLE_FILE="$KIT_ROOT/roles/${1%-[ab]}.md"
[ -f "$ROLE_FILE" ] || die "no role file $ROLE_FILE"
"$BIN_DIR/local-model-check.sh" >&2 || die "no session: KIT_LOCAL_MODEL did not pass bin/local-model-check.sh"
command -v qwen > /dev/null || die "qwen is not on PATH"

export KIT_ROLE="$1" KIT_HOST="qwen-code" KIT_HOST_PID="$$"
KIT_SESSION_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
export KIT_SESSION_ID
cd "$KIT_WORKTREE_ROOT"
# The round prompt is the host-neutral one from roles/START-HERE.md.
exec qwen --auth-type openai --model "$KIT_LOCAL_MODEL" --openai-api-key local \
  --openai-base-url "$KIT_LOCAL_BASE_URL" --session-id "$KIT_SESSION_ID" \
  -i "Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite deine Rolle laut $ROLE_FILE: ein Ticket zur Zeit, aufgreifen heisst sofort den In-Status setzen, kein Subagent."
