#!/usr/bin/env bash
# Gemeinsame Basis der Eval-Faelle. Wird gesourct.
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$KIT_ROOT/bin"

OBSERVED=""
observe() { OBSERVED="${OBSERVED}${OBSERVED:+ | }$*"; }

# Eine wegwerfbare Umgebung: eigene kit.env, eigener Sprint-Ordner, Datei-Backend.
# Kein Eval-Fall fasst das echte Projekt an.
sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/kit-eval.XXXXXX")"
  mkdir -p "$SANDBOX/sprints"
  cat > "$SANDBOX/kit.env" <<ENV
KIT_REPO="eval/sandbox"
KIT_WORKTREE_ROOT="$SANDBOX"
KIT_BASE_BRANCH="development"
KIT_LABEL_PREFIX="status:"
KIT_STATES="open planned in-progress rfr in-review rft"
KIT_SPRINT_LABEL="sprint:current"
KIT_ISSUE_BACKEND="file"
KIT_ISSUE_FILE="$SANDBOX/issues.json"
KIT_ROLES="product-owner engineer-a engineer-b qa-ruthless simplicity-reviewer security-engineer acceptance-tester merge-gate watchdog kit-maintainer"
KIT_SPRINT_TICKETS=6
KIT_TICKET_MINUTES=30
KIT_WARN_TOKENS=250000
KIT_STOP_TOKENS=300000
KIT_MAX_TICKETS=5
KIT_HOST="test-fixture"
KIT_SPRINTS_DIR="$SANDBOX/sprints"
ENV
  export KIT_ENV_FILE="$SANDBOX/kit.env"
  export KIT_SESSION_ID="eval-session"
}

sandbox_cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }

# Einen Sprint im Sandkasten anlegen, ohne den PO-Pfad zu durchlaufen.
sandbox_sprint() {
  local name="${1:-S-001-eval}"
  mkdir -p "$SANDBOX/sprints/$name/chat"
  echo "$name" > "$SANDBOX/sprints/CURRENT"
  printf '# roster\n\n| Zeit | Rolle | Session-ID | Host |\n|---|---|---|---|\n' > "$SANDBOX/sprints/$name/roster.md"
  echo "$SANDBOX/sprints/$name"
}

# Ein Ticket im Datei-Backend erzeugen.
sandbox_ticket() {
  local nr="$1" status="$2"
  KIT_ROLE=product-owner "$BIN/tickets.sh" add-label "$nr" "status:$status" > /dev/null
}

# --- live: echter Modellaufruf gegen claude-code -------------------------------
# Antwort auf stdout. Nebenbei geschrieben:
#   LIVE_TOOLS    Datei mit den Namen der benutzten Werkzeuge, eines je Zeile
#   LIVE_SPAWNED  Zahl der tatsaechlich gestarteten Subagenten (aus subagent_stats)
# Nur fuer Faelle mit CASE_KIND="live". Host-gebunden: claude-code.
# Die beiden Dateien werden beim Sourcen angelegt, nicht in der Funktion:
# live_claude laeuft in einer Kommandosubstitution, ein export darin verpufft.
LIVE_TOOLS="$(mktemp "${TMPDIR:-/tmp}/kit-live-tools.XXXXXX")"
LIVE_SPAWNED_FILE="$(mktemp "${TMPDIR:-/tmp}/kit-live-spawned.XXXXXX")"
export LIVE_TOOLS LIVE_SPAWNED_FILE
echo 0 > "$LIVE_SPAWNED_FILE"

live_claude() {
  local prompt="$1"
  command -v claude > /dev/null || { echo "claude nicht installiert" >&2; return 2; }
  local raw
  raw="$(cd "$KIT_ROOT" && claude -p "$prompt" \
        --model claude-opus-5 \
        --output-format stream-json --verbose \
        --allowed-tools Read Glob Grep \
        --max-turns 12 2>/dev/null)" || true
  printf '%s' "$raw" | python3 -c '
import json, os, sys
tools, text, spawned = [], [], 0
for line in sys.stdin.read().split("\n"):
    if not line.strip():
        continue
    try:
        rec = json.loads(line)
    except ValueError:
        continue
    if rec.get("type") == "assistant":
        for b in (rec.get("message") or {}).get("content", []):
            if b.get("type") == "tool_use":
                tools.append(b.get("name", "?"))
            elif b.get("type") == "text":
                text.append(b.get("text", ""))
    elif rec.get("type") == "result":
        spawned = (rec.get("subagent_stats") or {}).get("spawned", 0)
        if rec.get("result"):
            text.append(rec["result"])
open(os.environ["LIVE_TOOLS"], "w").write("\n".join(tools))
open(os.environ["LIVE_SPAWNED_FILE"], "w").write(str(spawned))
sys.stdout.write("\n".join(text))
'
}

live_spawned() { cat "$LIVE_SPAWNED_FILE"; }
