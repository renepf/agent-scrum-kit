#!/usr/bin/env bash
# Starts one interactive pi session for a role against the local model.
#   adapters/pi/start.sh <role>
#
# Refuses to start unless KIT_LOCAL_MODEL passes bin/local-model-check.sh: without tool calls a role cannot run
# bin/*.sh. pi reaches a local endpoint only through a provider in models.json (pi docs/models.md); measured
# 2026-09-15 with pi 0.85.1 under the provider names "ollama" and "kit-local". The kit does not write that file:
# it checks that provider "kit-local" points at KIT_LOCAL_BASE_URL and lists KIT_LOCAL_MODEL, and prints the
# entry to add if not. exec keeps this PID: KIT_HOST_PID is the single pi process.
source "$(dirname "${BASH_SOURCE[0]}")/../../bin/common.sh"
[ $# -eq 1 ] || die "usage: adapters/pi/start.sh <role>"
case " $KIT_ROLES " in *" $1 "*) ;; *) die "unknown role '$1'. Allowed: $KIT_ROLES" ;; esac
ROLE_FILE="$KIT_ROOT/roles/${1%-[ab]}.md"
[ -f "$ROLE_FILE" ] || die "no role file $ROLE_FILE"
"$BIN_DIR/local-model-check.sh" >&2 || die "no session: KIT_LOCAL_MODEL did not pass bin/local-model-check.sh"
command -v pi > /dev/null || die "pi is not on PATH"

MODELS="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/models.json"
python3 - "$MODELS" "$KIT_LOCAL_BASE_URL" "$KIT_LOCAL_MODEL" <<'PY' || exit 1
import json, sys
path, base, model = sys.argv[1:4]
entry = {"providers": {"kit-local": {"baseUrl": base, "api": "openai-completions", "apiKey": "local",
                                     "models": [{"id": model}]}}}
try:
    p = json.load(open(path, encoding="utf-8"))["providers"]["kit-local"]
    ok = p.get("baseUrl") == base and any(m.get("id") == model for m in p.get("models", []))
    why = "provider kit-local has baseUrl %r and models %r" % (p.get("baseUrl"), [m.get("id") for m in p.get("models", [])])
except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
    ok, why = False, "no provider kit-local (%s: %s)" % (type(e).__name__, e)
if not ok:
    sys.exit("FEHLER: %s: %s. Add, merged into any existing providers:\n%s" % (path, why, json.dumps(entry, indent=2)))
PY

export KIT_ROLE="$1" KIT_HOST="pi" KIT_HOST_PID="$$"
KIT_SESSION_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
export KIT_SESSION_ID
cd "$KIT_WORKTREE_ROOT"
# The round prompt is the host-neutral one from roles/START-HERE.md.
exec pi --provider kit-local --model "$KIT_LOCAL_MODEL" --session-id "$KIT_SESSION_ID" \
  "Fuehre bin/tick.sh aus. Liegt nichts fuer dich an, beende die Runde. Sonst arbeite deine Rolle laut $ROLE_FILE: ein Ticket zur Zeit, aufgreifen heisst sofort den In-Status setzen, kein Subagent."
