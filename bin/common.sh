#!/usr/bin/env bash
# Gemeinsame Basis fuer alle kit-Skripte. Wird gesourct, nie direkt ausgefuehrt.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$KIT_ROOT/bin"

die() { echo "FEHLER: $*" >&2; exit 1; }

# Konfiguration laden. Ohne kit.env laeuft nichts — das ist Absicht:
# das Template kennt kein Projekt, bis du es ihm sagst.
KIT_ENV="${KIT_ENV_FILE:-$KIT_ROOT/kit.env}"
[ -f "$KIT_ENV" ] || die "kit.env fehlt. 'cp kit.env.example kit.env' und ausfuellen (INSTALL.md)."
# shellcheck disable=SC1090
set -a; . "$KIT_ENV"; set +a

: "${KIT_REPO:?KIT_REPO fehlt in kit.env}"
: "${KIT_ROLES:?KIT_ROLES fehlt in kit.env}"
: "${KIT_STATUS_MAP:?KIT_STATUS_MAP fehlt in kit.env}"
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

case "$KIT_REPO" in UNKNOWN*) die "KIT_REPO steht noch auf UNKNOWN. Erst kit.env ausfuellen." ;; esac

# Board-IDs sind generiert (bin/board-check.sh --write), nie handgeschrieben.
BOARD_ENV="${KIT_BOARD_ENV_FILE:-$KIT_ROOT/board.env}"
# shellcheck disable=SC1090
[ -f "$BOARD_ENV" ] && { set -a; . "$BOARD_ENV"; set +a; }

KIT_STATES="$(printf '%s\n' "$KIT_STATUS_MAP" | grep '|' | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"

SPRINTS_DIR="${KIT_SPRINTS_DIR:-$KIT_ROOT/sprints}"
CURRENT_FILE="$SPRINTS_DIR/CURRENT"
MEMORY_DIR="${KIT_MEMORY_DIR:-$KIT_ROOT/memory}"

# Board-Name zu einem Statusschluessel.
board_name() { printf '%s\n' "$KIT_STATUS_MAP" | grep "^$1|" | cut -d'|' -f2; }

# Der aktive Sprint steht als Ordnername in sprints/CURRENT.
sprint_dir() {
  [ -f "$CURRENT_FILE" ] || die "kein aktiver Sprint — sprints/CURRENT fehlt. Erst 'bin/sprint-new.sh <slug> <ticket...>' laufen lassen."
  local name
  name="$(tr -d '[:space:]' < "$CURRENT_FILE")"
  [ -n "$name" ] || die "sprints/CURRENT ist leer"
  [ -d "$SPRINTS_DIR/$name" ] || die "Sprint-Ordner $SPRINTS_DIR/$name existiert nicht"
  echo "$SPRINTS_DIR/$name"
}

# Rollen-Anker: .pid-roles/<host-pid> enthaelt die Rolle des Host-Prozesses dieser Session.
# Ein Kontext-Reset im Host (z.B. /clear bei claude-code) beendet den Prozess nicht, vergibt aber
# eine neue Session-ID und loescht die Rolle aus dem Kontext. Die PID ueberlebt — der Anker auch.
PID_ROLES="$KIT_ROOT/.pid-roles"

# Die Rolle: zuerst KIT_ROLE aus der Umgebung, sonst der Anker des Host-Prozesses.
role() {
  if [ -z "${KIT_ROLE:-}" ]; then
    local hp; hp="$(host_pid)"
    [ -n "$hp" ] && [ -f "$PID_ROLES/$hp" ] && KIT_ROLE="$(cat "$PID_ROLES/$hp")"
  fi
  [ -n "${KIT_ROLE:-}" ] || die "Rolle unbekannt: weder KIT_ROLE gesetzt noch Anker in .pid-roles/ fuer diesen Host-Prozess. Einmal mit KIT_ROLE=<rolle> bin/tick.sh ausfuehren."
  case " $KIT_ROLES " in
    *" $KIT_ROLE "*) echo "$KIT_ROLE" ;;
    *) die "unbekannte Rolle '$KIT_ROLE'. Erlaubt: $KIT_ROLES" ;;
  esac
}

# Session-ID. Wie sie ermittelt wird, weiss nur der Host-Adapter.
# adapters/<host>/session-id.sh druckt sie auf stdout oder scheitert. Nie raten.
session_id() {
  if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; return; fi
  local probe="$KIT_ROOT/adapters/$KIT_HOST/session-id.sh"
  [ -x "$probe" ] || die "keine Session-ID: adapters/$KIT_HOST/session-id.sh fehlt. KIT_SESSION_ID von Hand setzen."
  "$probe" || die "adapters/$KIT_HOST/session-id.sh hat keine Session-ID geliefert — Fehlschlag, nicht raten."
}

# PID des Host-Prozesses dieser Session (fuer die Zwillingssperre). Leer = unbekannt.
host_pid() {
  if [ -n "${KIT_HOST_PID:-}" ]; then echo "$KIT_HOST_PID"; return; fi
  local probe="$KIT_ROOT/adapters/$KIT_HOST/host-pid.sh"
  [ -x "$probe" ] && "$probe" 2>/dev/null || true
}

now() { date '+%Y-%m-%d %H:%M'; }

# Anker fuer die eigene Rolle setzen, wenn er fehlt oder abweicht. Ohne Host-PID: nichts.
anchor_role() {
  local r="$1" hp; hp="$(host_pid)"
  [ -n "$hp" ] || return 0
  [ "$(cat "$PID_ROLES/$hp" 2>/dev/null)" = "$r" ] && return 0
  mkdir -p "$PID_ROLES"; printf '%s\n' "$r" | atomic_write "$PID_ROLES/$hp"
}

# Alle Sessions laufen auf derselben Maschine im selben Ordner. Sie sehen die
# Schreibvorgaenge der anderen sofort ueber das Dateisystem — Git wird zum Lesen NICHT
# gebraucht. Deshalb committet und pusht genau EINE Rolle: der watchdog, im Takt.
kit_commit_all() {
  local msg="$1"
  [ "$(role)" = "watchdog" ] || die "nur der watchdog committet den Sprint-Stand"
  cd "$KIT_ROOT"
  git add -A
  git diff --cached --quiet && return 0
  git commit -q -m "$msg"
  git pull --rebase -q
  git push -q
}

# Deterministische Datei atomar ersetzen: erst temporaer schreiben, dann umbenennen.
atomic_write() {
  local target="$1" tmp
  tmp="$(mktemp "${target}.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$target"
}

# Anhaengen unter Sperre. mkdir ist atomar auf jedem POSIX-Dateisystem.
with_lock() {
  local lock="$1"; shift
  local tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 300 ] || die "Sperre $lock seit 30s belegt — haengende Session pruefen"
    sleep 0.1
  done
  # shellcheck disable=SC2064
  trap "rmdir '$lock' 2>/dev/null || true" EXIT
  "$@"
  rmdir "$lock" 2>/dev/null || true
  trap - EXIT
}

# Welche der verlangten Verdicts fehlen im verknuepften PR fuer dessen AKTUELLEN HEAD?
# Ein Push nach dem Review entwertet alte Verdicts. Format je Verdict, erste Zeile:
#   <VERDICT> — HEAD `<sha8>`, ...
# Setzt VERDICT_MISSING (leer = alle da), VERDICT_PR, VERDICT_HEAD8. Direkt aufrufen, nie in $(…).
verdicts_missing() {
  local ticket="$1"; shift
  local pr_line pr head8 v missing=""
  pr_line="$("$BIN_DIR/tickets.sh" pr "$ticket")" || die "#$ticket: kein verknuepfter PR lesbar — Zustand pruefen, nicht raten"
  pr="${pr_line%% *}"; head8="${pr_line##* }"
  [ -n "$pr" ] && [ -n "$head8" ] && [ "$pr" != "$head8" ] || die "#$ticket: PR oder HEAD nicht lesbar ('$pr_line')"
  local bodies
  bodies="$("$BIN_DIR/tickets.sh" pr-comments "$pr")" || die "PR #$pr: Kommentare nicht lesbar — nicht raten"
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
