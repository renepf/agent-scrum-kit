#!/usr/bin/env bash
# Shared base for every kit script. Sourced, never executed directly.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$KIT_ROOT/bin"

die() { echo "ERROR: $*" >&2; exit 1; }

# Load the configuration. Without kit.env nothing runs — that is deliberate:
# the template knows no project until you tell it one.
KIT_ENV="${KIT_ENV_FILE:-$KIT_ROOT/kit.env}"
[ -f "$KIT_ENV" ] || die "kit.env is missing. 'cp kit.env.example kit.env' and fill it in (INSTALL.md)."
# shellcheck disable=SC1090
set -a; . "$KIT_ENV"; set +a

: "${KIT_REPO:?KIT_REPO is missing in kit.env}"
: "${KIT_ROLES:?KIT_ROLES is missing in kit.env}"
: "${KIT_STATUS_MAP:?KIT_STATUS_MAP is missing in kit.env}"
: "${KIT_LABEL_PREFIX:=status:}"
: "${KIT_OWNER_PREFIX:=owner:}"
: "${KIT_SPRINT_LABEL:=sprint:current}"
: "${KIT_ISSUE_BACKEND:=gh}"
: "${KIT_BOARD:=none}"
: "${KIT_HOST:=claude-code}"
: "${KIT_WARN_TOKENS:=250000}"
: "${KIT_STOP_TOKENS:=300000}"
: "${KIT_MAX_TICKETS:=5}"
: "${KIT_LEASE_MINUTES:=20}"
: "${KIT_QUEUE_MAP:=}"

case "$KIT_REPO" in UNKNOWN*) die "KIT_REPO still says UNKNOWN. Fill in kit.env first." ;; esac

# Board IDs are generated (bin/board-check.sh --write), never handwritten.
BOARD_ENV="${KIT_BOARD_ENV_FILE:-$KIT_ROOT/board.env}"
# shellcheck disable=SC1090
[ -f "$BOARD_ENV" ] && { set -a; . "$BOARD_ENV"; set +a; }

KIT_STATES="$(printf '%s\n' "$KIT_STATUS_MAP" | grep '|' | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"

SPRINTS_DIR="${KIT_SPRINTS_DIR:-$KIT_ROOT/sprints}"
CURRENT_FILE="$SPRINTS_DIR/CURRENT"
MEMORY_DIR="${KIT_MEMORY_DIR:-$KIT_ROOT/memory}"
# Gate ledger per ticket: $TICKETS_DIR/<nr>/GATES.md (format: bin/gates.py).
TICKETS_DIR="${KIT_TICKETS_DIR:-$KIT_ROOT/tickets}"

# Board name for a status key.
board_name() { printf '%s\n' "$KIT_STATUS_MAP" | grep "^$1|" | cut -d'|' -f2; }

# The active sprint is the folder name in sprints/CURRENT.
sprint_dir() {
  [ -f "$CURRENT_FILE" ] || die "no active sprint — sprints/CURRENT is missing. Run 'bin/sprint-new.sh <slug> <ticket...>' first."
  local name
  name="$(tr -d '[:space:]' < "$CURRENT_FILE")"
  [ -n "$name" ] || die "sprints/CURRENT is empty"
  [ -d "$SPRINTS_DIR/$name" ] || die "sprint folder $SPRINTS_DIR/$name does not exist"
  echo "$SPRINTS_DIR/$name"
}

# Role anchor: .pid-roles/<host-pid> holds the role of this session's host process.
# A context reset in the host (for example /clear in claude-code) does not end the process, but it
# hands out a new session id and drops the role from the context. The PID survives — so does the anchor.
PID_ROLES="$KIT_ROOT/.pid-roles"

# The role: KIT_ROLE from the environment first, otherwise the anchor of the host process.
role() {
  if [ -z "${KIT_ROLE:-}" ]; then
    local hp; hp="$(host_pid)"
    [ -n "$hp" ] && [ -f "$PID_ROLES/$hp" ] && KIT_ROLE="$(cat "$PID_ROLES/$hp")"
  fi
  [ -n "${KIT_ROLE:-}" ] || die "role unknown: neither KIT_ROLE set nor an anchor in .pid-roles/ for this host process. Run bin/tick.sh once with KIT_ROLE=<role>."
  case " $KIT_ROLES " in
    *" $KIT_ROLE "*) echo "$KIT_ROLE" ;;
    *) die "unknown role '$KIT_ROLE'. Allowed: $KIT_ROLES" ;;
  esac
}

# Session id. Only the host adapter knows how it is obtained.
# adapters/<host>/session-id.sh prints it on stdout or fails. Never guess.
session_id() {
  if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; return; fi
  local probe="$KIT_ROOT/adapters/$KIT_HOST/session-id.sh"
  [ -x "$probe" ] || die "no session id: adapters/$KIT_HOST/session-id.sh is missing. Set KIT_SESSION_ID by hand."
  "$probe" || die "adapters/$KIT_HOST/session-id.sh returned no session id — a failure, not something to guess."
}

# Does a host process live under this PID? Not merely "some process lives": a PID is handed out again
# after the process ends (reference 2026-09-14: an anchor later pointed at cfprefsd). Which process name
# is a host only the adapter knows; without adapters/<host>/host-alive.sh it stays at kill -0.
host_alive() {
  local pid="$1" probe="$KIT_ROOT/adapters/$KIT_HOST/host-alive.sh"
  [ -n "$pid" ] && [ "$pid" != "-" ] || return 1
  if [ -x "$probe" ]; then "$probe" "$pid"; else kill -0 "$pid" 2>/dev/null; fi
}

# PID of this session's host process (for the twin lock). Empty = unknown.
host_pid() {
  if [ -n "${KIT_HOST_PID:-}" ]; then echo "$KIT_HOST_PID"; return; fi
  local probe="$KIT_ROOT/adapters/$KIT_HOST/host-pid.sh"
  [ -x "$probe" ] && "$probe" 2>/dev/null || true
}

now() { date '+%Y-%m-%d %H:%M'; }

# Wake marks: whoever has this state in their queue should not wait for the next interval.
# The mark is a hint, not an order — if it is left lying around, the interval wakes the role
# anyway.
wake_roles() {
  local state="$1" line role queue
  mkdir -p "$KIT_ROOT/.role-loop" 2>/dev/null || return 0
  printf '%s\n' "$KIT_QUEUE_MAP" | grep '|' | while IFS='|' read -r role queue; do
    [ -n "$role" ] || continue
    case ",$queue," in
      *",$state,"*|*"*"*) : > "$KIT_ROOT/.role-loop/$role.wake" 2>/dev/null || true ;;
    esac
  done
}

# Set the anchor for your own role when it is missing or differs. Without a host PID: nothing.
anchor_role() {
  local r="$1" hp; hp="$(host_pid)"
  [ -n "$hp" ] || return 0
  [ "$(cat "$PID_ROLES/$hp" 2>/dev/null)" = "$r" ] && return 0
  mkdir -p "$PID_ROLES"; printf '%s\n' "$r" | atomic_write "$PID_ROLES/$hp"
}

# Every session runs on the same machine in the same folder. They see each other's writes
# immediately through the file system — git is NOT needed to read. That is why exactly ONE role
# commits and pushes: the watchdog, on its interval.
kit_commit_all() {
  local msg="$1"
  [ "$(role)" = "watchdog" ] || die "only the watchdog commits the sprint state"
  cd "$KIT_ROOT"
  git add -A
  git diff --cached --quiet && return 0
  git commit -q -m "$msg"
  git pull --rebase -q
  git push -q
}

# Replace a deterministic file atomically: write to a temporary file first, then rename.
atomic_write() {
  local target="$1" tmp
  tmp="$(mktemp "${target}.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$target"
}

# Approved OWNS of the other open sprint tickets, one line per "#<nr><TAB><globs>" (for gates.py overlap).
# A ticket without an approval (still backlog) holds nothing. An unreadable call aborts instead of reporting nothing.
# Call: CLAIMS="$(sprint_claims <nr>)" || exit 1
sprint_claims() {
  local self="$1" nrs o c a
  nrs="$("$BIN_DIR/tickets.sh" sprint | python3 -c 'import json,sys; print(" ".join(str(i["number"]) for i in json.load(sys.stdin)))')" \
    || die "sprint tickets not readable — a failure, not a state"
  for o in $nrs; do
    [ "$o" != "$self" ] || continue
    c="$("$BIN_DIR/tickets.sh" comments "$o")" || die "#$o: comments not readable — a failure, not a state"
    a="$(printf '%s' "$c" | python3 "$BIN_DIR/gates.py" approved)" || continue
    printf '#%s\t%s\n' "$o" "${a#*$'\t'}"
  done
}

# Append under a lock. mkdir is atomic on every POSIX file system.
with_lock() {
  local lock="$1"; shift
  local tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 300 ] || die "lock $lock held for 30s — check for a hanging session"
    sleep 0.1
  done
  # shellcheck disable=SC2064
  trap "rmdir '$lock' 2>/dev/null || true" EXIT
  # The exit code of the command belongs to the caller: otherwise a failure INSIDE the lock
  # disappears without a trace, and "it ran" reads like "it worked".
  local rc=0
  "$@" || rc=$?
  rmdir "$lock" 2>/dev/null || true
  trap - EXIT
  return "$rc"
}

# Which of the required verdicts are missing in the linked PR for its CURRENT HEAD?
# A push after the review invalidates old verdicts. Format per verdict, first line:
#   <VERDICT> — HEAD `<sha8>`, ...
# Sets VERDICT_MISSING (empty = all there), VERDICT_PR, VERDICT_HEAD8. Call directly, never in $(…).
verdicts_missing() {
  local ticket="$1"; shift
  local pr_line pr head8 v missing=""
  pr_line="$("$BIN_DIR/tickets.sh" pr "$ticket")" || die "#$ticket: no linked PR readable — check the state, do not guess"
  pr="${pr_line%% *}"; head8="${pr_line##* }"
  [ -n "$pr" ] && [ -n "$head8" ] && [ "$pr" != "$head8" ] || die "#$ticket: PR or HEAD not readable ('$pr_line')"
  local bodies
  bodies="$("$BIN_DIR/tickets.sh" pr-comments "$pr")" || die "PR #$pr: comments not readable — do not guess"
  for v in "$@"; do
    printf '%s\n' "$bodies" | python3 -c '
import json, sys
v, head = sys.argv[1], sys.argv[2]
bodies = json.loads(sys.stdin.read() or "[]")
ok = any(b.splitlines()[0].startswith(v) and head in b.splitlines()[0] for b in bodies if b.strip())
sys.exit(0 if ok else 1)
' "$v" "$head8" || missing="$missing '$v'"
  done
  VERDICT_PR="$pr"; VERDICT_HEAD8="$head8"; VERDICT_MISSING="$missing"
}
