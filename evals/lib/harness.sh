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
  mkdir -p "$SANDBOX/sprints" "$SANDBOX/memory"
  cp "$KIT_ROOT/kit.env.example" "$SANDBOX/kit.env"
  cat >> "$SANDBOX/kit.env" <<ENV

# --- Sandbox-Ueberschreibungen (evals/lib/harness.sh) ---
KIT_REPO="eval/sandbox"
KIT_WORKTREE_ROOT="$SANDBOX"
KIT_ISSUE_BACKEND="file"
KIT_ISSUE_FILE="$SANDBOX/issues.json"
KIT_BOARD="none"
KIT_HOST="test-fixture"
KIT_SPRINTS_DIR="$SANDBOX/sprints"
KIT_MEMORY_DIR="$SANDBOX/memory"
KIT_TICKETS_DIR="$SANDBOX/tickets"
ENV
  export KIT_ENV_FILE="$SANDBOX/kit.env"
  export KIT_BOARD_ENV_FILE="$SANDBOX/board.env"
  export KIT_SESSION_ID="eval-session"
  export KIT_HOST_PID="$$"
}

# Ein Ticket-Zustand direkt ins Datei-Backend schreiben (Titel, Labels, PR, Kommentare).
#   sandbox_issue 7 '{"labels":["status:rfr"],"pr":{"number":70,"head":"abcdef0123","comments":[],"checks":"pass"}}'
sandbox_issue() {
  python3 - "$SANDBOX/issues.json" "$1" "$2" <<'PY2'
import json, os, sys
path, n, patch = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
db = json.load(open(path)) if os.path.exists(path) else {}
i = db.setdefault(n, {"title": "eval", "labels": [], "assignees": [], "comments": [], "state": "open"})
i.update(patch)
json.dump(db, open(path, "w"), indent=2, sort_keys=True)
PY2
}

# Einen PR-Kommentar anhaengen (Verdict).
sandbox_pr_comment() {
  python3 - "$SANDBOX/issues.json" "$1" "$2" <<'PY2'
import json, sys
path, n, body = sys.argv[1], sys.argv[2], sys.argv[3]
db = json.load(open(path)); db[n]["pr"].setdefault("comments", []).append(body)
json.dump(db, open(path, "w"), indent=2, sort_keys=True)
PY2
}

# Sortiert: das Backend liefert Einfuegereihenfolge, verglichen wird der Inhalt.
sandbox_labels() { KIT_ROLE=product-owner "$BIN/tickets.sh" labels "$1" | grep . | sort | tr '\n' ' ' | sed 's/ $//'; }

sandbox_cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }

# Ein Gate-Ledger fuer ein Ticket schreiben, Text auf stdin.
# Schreibt zugleich die Artefaktkette, die planned verlangt (Fall 46). Ein Fall, der sie pruefen will,
# loescht oder leert sie selbst.
sandbox_ledger() {
  mkdir -p "$SANDBOX/tickets/$1"
  cat > "$SANDBOX/tickets/$1/GATES.md"
  for a in intent.md spec.md plan.md; do printf 'eval\n' > "$SANDBOX/tickets/$1/$a"; done
}

# Zustand eines Tickets fuer "eine Ablehnung schreibt nichts": Issue-Eintrag plus jede Datei unter tickets/<nr>/.
sandbox_snap() {
  python3 - "$SANDBOX" "$1" <<'PY2'
import hashlib, json, os, sys
root, n = sys.argv[1], sys.argv[2]
path = os.path.join(root, "issues.json")
print(json.dumps(json.load(open(path)).get(n) if os.path.exists(path) else None, sort_keys=True))
for base, _, files in sorted(os.walk(os.path.join(root, "tickets", n))):
    for f in sorted(files):
        p = os.path.join(base, f)
        print(os.path.relpath(p, root), hashlib.sha256(open(p, "rb").read()).hexdigest())
PY2
}

# Jedes Gate eines Tickets gruen fuer den HEAD seines PR, im Belegformat von bin/gates.py (ausfuehrbar: Definition
# gebunden, manuell: belegt), dazu ein QA-PASS mit einer Mutationszeile je ausfuehrbarem Gate. Mit $2=nurgates ohne
# den QA-Kommentar. Ohne Ledger vorher ein planbares Ledger. Fuer Faelle, die nicht die Gates pruefen.
sandbox_gates_green() {
  [ -f "$SANDBOX/tickets/$1/GATES.md" ] || sandbox_plannable "$1"
  python3 - "$BIN" "$SANDBOX/issues.json" "$SANDBOX/tickets/$1/GATES.md" "$1" "${2:-}" <<'PY2'
import json, sys
sys.path.insert(0, sys.argv[1])
import gates
db = json.load(open(sys.argv[2])); head = db[sys.argv[4]]["pr"]["head"][:8]
path = sys.argv[3]; text = open(path).read(); doc = gates.parse(text)
gates.write_results(path, text, doc, {
    g["id"]: (True, "manual head=%s by=eval at=eval — eval" % head if g["check"] is None else
              "v1 head=%s def=%s exit=0 expect=matched out=eval at=eval by=eval" % (head, gates.definition_digest(g)))
    for g in doc["gates"]})
if sys.argv[5] != "nurgates":
    lines = ["%s: Mutation eval → rot" % g["id"] for g in doc["gates"] if g["check"] is not None]
    db[sys.argv[4]]["pr"].setdefault("comments", []).append("QA PASS — HEAD `%s`, eval\n%s" % (head, "\n".join(lines)))
    json.dump(db, open(sys.argv[2], "w"), indent=2, sort_keys=True)
PY2
}

# Ein Ticket planbar machen: Issue mit AC-1, Ledger mit genau einem Gate dafuer, OWNS als $2.
# Hat das Ticket schon einen PR, bekommt er eine Datei im Umfang: eine leere Dateiliste lehnt rfr ab.
sandbox_plannable() {
  sandbox_issue "$1" '{"body":"AC-1: das Ergebnis ist beobachtbar"}'
  python3 - "$SANDBOX/issues.json" "$1" <<'PY2'
import json, sys
path, n = sys.argv[1:3]
db = json.load(open(path))
if db[n].get("pr") is not None:
    db[n]["pr"].setdefault("files", ["src/eval.py"])
json.dump(db, open(path, "w"), indent=2, sort_keys=True)
PY2
  sandbox_ledger "$1" <<LEDGER
# Gates: eval

OWNS: ${2:-src/**, tests/**}

- [ ] AC-1: das Ergebnis ist beobachtbar
  CHECK: python3 tools/check_result.py
  EXPECT: ergebnis geprueft
  EVIDENCE: pending
LEDGER
}

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
  [ "$status" = "backlog" ] && { sandbox_issue "$nr" '{}'; return; }
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
# Stellt ein zustandsbehaftetes gh vor den PATH, schaltet das Board ein und schreibt board.env.
#   fake_gh '{"7": {"labels": ["status:planned"], ...}}'
# Danach: "$FAKE_GH_LOG" (Aufrufreihenfolge), fake_gh_get <nr> <feld>.
fake_gh() {
  mkdir -p "$SANDBOX/fakebin"
  cp "$KIT_ROOT/evals/lib/fake-gh" "$SANDBOX/fakebin/gh"
  export FAKE_GH_STATE="$SANDBOX/gh-state.json" FAKE_GH_LOG="$SANDBOX/gh.log" FAKE_GH_FAIL=""
  # Board-Namen enthalten Leerzeichen, deshalb ';' als Trenner.
  export FAKE_GH_OPTIONS="o-backlog=Backlog;o-planned=Planned;o-inprogress=In progress;o-rfr=RfR;o-inreview=In review;o-rft=RfT;o-intesting=In Testing;o-done=Done"
  printf '%s' "$1" > "$FAKE_GH_STATE"
  : > "$FAKE_GH_LOG"
  export PATH="$SANDBOX/fakebin:$PATH"
  cat >> "$SANDBOX/kit.env" <<'ENV'
KIT_ISSUE_BACKEND="gh"
KIT_BOARD="github-project"
KIT_PROJECT_OWNER="eval"
KIT_PROJECT_NUMBER="1"
ENV
  cat > "$KIT_BOARD_ENV_FILE" <<'ENV'
KIT_PROJECT_ID="PVT_eval"
KIT_STATUS_FIELD_ID="PVTSSF_eval"
KIT_OPTION_BACKLOG="o-backlog"
KIT_OPTION_PLANNED="o-planned"
KIT_OPTION_IN_PROGRESS="o-inprogress"
KIT_OPTION_RFR="o-rfr"
KIT_OPTION_IN_REVIEW="o-inreview"
KIT_OPTION_RFT="o-rft"
KIT_OPTION_IN_TESTING="o-intesting"
KIT_OPTION_DONE="o-done"
ENV
}

fake_gh_get() {
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]]; print(" ".join(v) if isinstance(v, list) else v)' \
    "$FAKE_GH_STATE" "$1" "$2"
}
