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
KIT_STATES="backlog planned in-progress rfr in-review rft in-testing done"
KIT_SPRINT_LABEL="sprint:current"
KIT_ISSUE_BACKEND="file"
KIT_ISSUE_FILE="$SANDBOX/issues.json"
KIT_ROLES="product-owner engineer-a engineer-b qa-ruthless simplicity-reviewer security-engineer acceptance-tester merge-gate watchdog kit-maintainer"
KIT_QUEUES="product-owner=* engineer-a=planned engineer-b=planned qa-ruthless=rfr simplicity-reviewer=rfr security-engineer=rfr acceptance-tester=rft merge-gate=in-testing"
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
LIVE_BLOCKED_FILE="$(mktemp "${TMPDIR:-/tmp}/kit-live-blocked.XXXXXX")"
export LIVE_TOOLS LIVE_SPAWNED_FILE LIVE_BLOCKED_FILE
echo 0 > "$LIVE_SPAWNED_FILE"
: > "$LIVE_BLOCKED_FILE"

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

# Ein erschoepftes Kontingent, ein Netzfehler oder eine leere Antwort sind ein FEHLSCHLAG,
# kein Ergebnis. Ein Fall, der so endet, ist BLOCKIERT — nie "durchgefallen". Sonst liest
# sich die Kontingentgrenze wie ein Rollenfehler, und genau das ist der Fehler, den die
# Familie Anti-Halluzination verbietet.
live_blocked() {
  local antwort="$1"
  case "$antwort" in
    *"hit your session limit"*|*"usage limit"*|*"rate limit"*|*"Rate limit"*|*"Credit balance"*|*"overloaded"*|*"API Error"*)
      echo "Kontingent oder API: $(printf '%s' "$antwort" | tr '\n' ' ' | cut -c1-80)" > "$LIVE_BLOCKED_FILE"; return 0 ;;
  esac
  if [ -z "$(printf '%s' "$antwort" | tr -d '[:space:]')" ]; then
    echo "leere Antwort vom Host" > "$LIVE_BLOCKED_FILE"; return 0
  fi
  return 1
}

# Am Anfang jeder Auswertung aufrufen. Exitcode 3 = blockiert, von run.sh eigens behandelt.
live_guard() {
  if live_blocked "$1"; then
    echo "BEOBACHTET: BLOCKIERT — $(cat "$LIVE_BLOCKED_FILE")"
    exit 3
  fi
}

# --- vorgetaeuschtes gh ----------------------------------------------------------
# Stellt ein zustandsbehaftetes gh vor den PATH und schreibt eine kit.env mit Board.
#   fake_gh '{"7": {"labels": ["status:planned"], ...}}'
# Danach: "$FAKE_GH_LOG" (Aufrufreihenfolge), fake_gh_get <nr> <feld>.
fake_gh() {
  mkdir -p "$SANDBOX/fakebin"
  cp "$KIT_ROOT/evals/lib/fake-gh" "$SANDBOX/fakebin/gh"
  export FAKE_GH_STATE="$SANDBOX/gh-state.json" FAKE_GH_LOG="$SANDBOX/gh.log" FAKE_GH_FAIL=""
  printf '%s' "$1" > "$FAKE_GH_STATE"
  : > "$FAKE_GH_LOG"
  export PATH="$SANDBOX/fakebin:$PATH"
  cat > "$SANDBOX/board.env" <<ENV
$(cat "$SANDBOX/kit.env")
KIT_ISSUE_BACKEND="gh"
KIT_PROJECT_ID="PVT_eval"
KIT_STATUS_FIELD_ID="PVTSSF_eval"
KIT_STATUS_OPTIONS="backlog=o-backlog planned=o-planned in-progress=o-inprogress rfr=o-rfr in-review=o-inreview rft=o-rft in-testing=o-intesting done=o-done"
ENV
}

fake_gh_get() {
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]]; print(" ".join(v) if isinstance(v, list) else v)' \
    "$FAKE_GH_STATE" "$1" "$2"
}
