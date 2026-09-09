#!/usr/bin/env bash
# Gemeinsame Basis fuer alle kit-Skripte. Wird gesourct, nie direkt ausgefuehrt.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Konfiguration laden. Ohne kit.env laeuft nichts — das ist Absicht:
# das Template kennt kein Projekt, bis du es ihm sagst.
KIT_ENV="${KIT_ENV_FILE:-$KIT_ROOT/kit.env}"

die() { echo "FEHLER: $*" >&2; exit 1; }

[ -f "$KIT_ENV" ] || die "kit.env fehlt. 'cp kit.env.example kit.env' und ausfuellen."
# shellcheck disable=SC1090
set -a; . "$KIT_ENV"; set +a

: "${KIT_REPO:?KIT_REPO fehlt in kit.env}"
: "${KIT_ROLES:?KIT_ROLES fehlt in kit.env}"
: "${KIT_STATES:?KIT_STATES fehlt in kit.env}"
: "${KIT_LABEL_PREFIX:=status:}"
: "${KIT_ISSUE_BACKEND:=gh}"
: "${KIT_HOST:=claude-code}"
: "${KIT_WARN_TOKENS:=250000}"
: "${KIT_STOP_TOKENS:=300000}"

case "$KIT_REPO" in
  UNKNOWN*) die "KIT_REPO steht noch auf UNKNOWN. Erst kit.env ausfuellen." ;;
esac

SPRINTS_DIR="${KIT_SPRINTS_DIR:-$KIT_ROOT/sprints}"
CURRENT_FILE="$SPRINTS_DIR/CURRENT"

# Der aktive Sprint steht als Ordnername in sprints/CURRENT.
sprint_dir() {
  [ -f "$CURRENT_FILE" ] || die "kein aktiver Sprint — sprints/CURRENT fehlt. Erst 'bin/sprint-new.sh <slug> <ticket...>' laufen lassen."
  local name
  name="$(tr -d '[:space:]' < "$CURRENT_FILE")"
  [ -n "$name" ] || die "sprints/CURRENT ist leer"
  [ -d "$SPRINTS_DIR/$name" ] || die "Sprint-Ordner $SPRINTS_DIR/$name existiert nicht"
  echo "$SPRINTS_DIR/$name"
}

# Die Rolle kommt aus der Umgebung des Terminals: export KIT_ROLE=engineer-a
role() {
  [ -n "${KIT_ROLE:-}" ] || die "KIT_ROLE ist nicht gesetzt. Im Terminal: export KIT_ROLE=<rolle>"
  case " $KIT_ROLES " in
    *" $KIT_ROLE "*) echo "$KIT_ROLE" ;;
    *) die "unbekannte Rolle '$KIT_ROLE'. Erlaubt: $KIT_ROLES" ;;
  esac
}

# Session-ID. Wie sie ermittelt wird, weiss nur der Host-Adapter.
# adapters/<host>/session-id.sh druckt sie auf stdout oder scheitert.
session_id() {
  if [ -n "${KIT_SESSION_ID:-}" ]; then echo "$KIT_SESSION_ID"; return; fi
  local probe="$KIT_ROOT/adapters/$KIT_HOST/session-id.sh"
  [ -x "$probe" ] || die "keine Session-ID: adapters/$KIT_HOST/session-id.sh fehlt oder ist nicht ausfuehrbar. KIT_SESSION_ID von Hand setzen."
  "$probe" || die "adapters/$KIT_HOST/session-id.sh hat keine Session-ID geliefert — Fehlschlag, nicht raten."
}

now() { date '+%Y-%m-%d %H:%M'; }

# Alle Sessions laufen auf derselben Maschine im selben Ordner. Sie sehen die
# Schreibvorgaenge der anderen sofort ueber das Dateisystem — Git wird zum Lesen NICHT
# gebraucht. Deshalb committet und pusht genau EINE Rolle: der watchdog, im Takt.
# Damit gibt es keinen parallelen Rebase und keinen verlorenen Chat-Eintrag.
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
# Zwei gleichzeitige Laeufe erzeugen denselben Inhalt, der letzte gewinnt vollstaendig.
# Ein halb geschriebener Index kann so nie gelesen werden.
atomic_write() {
  local target="$1" tmp
  tmp="$(mktemp "${target}.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$target"
}

# Anhaengen unter Sperre. Zwei Sessions, die gleichzeitig in DIESELBE Datei schreiben,
# verlieren sonst eine Zeile. mkdir ist atomar auf jedem POSIX-Dateisystem.
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
