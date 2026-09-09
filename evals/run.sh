#!/usr/bin/env bash
# Eval-Suite. Ein Befehl, je Fall bestanden/durchgefallen mit dem beobachteten Wert.
#
#   evals/run.sh                 # alle Faelle ausser den live-Faellen
#   evals/run.sh --live          # zusaetzlich die Faelle mit echtem Modellaufruf
#   evals/run.sh --case <name>   # genau einen Fall
#   evals/run.sh --list          # nur auflisten
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE=0; ONLY=""; LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE=1 ;;
    --case) ONLY="${2:-}"; shift ;;
    --list) LIST=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unbekannte Option: $1" >&2; exit 2 ;;
  esac
  shift
done

PASS=0; FAIL=0; SKIP=0; BLOCKED=0
FAILED_CASES=""

printf '%s\n' "── agent-scrum-kit · Eval-Suite ────────────────────────────────"
printf 'live-Faelle: %s\n\n' "$([ "$LIVE" = 1 ] && echo "an" || echo "aus (--live schaltet sie ein)")"

for f in "$HERE"/cases/*.sh; do
  name="$(basename "$f" .sh)"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || [ "$ONLY" = "${name#*-}" ] || continue

  # Meta ohne Ausfuehrung lesen.
  DESC="$(grep -m1 '^CASE_DESC=' "$f" | cut -d= -f2- | tr -d '"')"
  KIND="$(grep -m1 '^CASE_KIND=' "$f" | cut -d= -f2- | tr -d '"')"
  HOST="$(grep -m1 '^CASE_HOST=' "$f" | cut -d= -f2- | tr -d '"')"

  if [ "$LIST" = 1 ]; then
    printf '%-34s %-8s %s\n' "$name" "$KIND" "$DESC"
    continue
  fi

  if [ "$KIND" = "live" ] && [ "$LIVE" != 1 ]; then
    printf '  \033[33mSKIP\033[0m  %-30s %s\n' "$name" "braucht --live"
    SKIP=$((SKIP + 1)); continue
  fi

  out="$(bash "$f" 2>&1)"; rc=$?
  obs="$(printf '%s' "$out" | grep '^BEOBACHTET:' | sed 's/^BEOBACHTET: //' | tr '\n' ' ')"
  tag=""
  [ -n "$HOST" ] && tag=" [host-gebunden: $HOST]"

  # Exitcode 3 = der Host konnte nicht antworten (Kontingent, Netz, leere Antwort).
  # Das ist ein Fehlschlag des Laufs, kein Urteil ueber die Rolle.
  if [ "$rc" = 3 ]; then
    printf '  \033[33mBLOCK\033[0m %-30s %s%s\n' "$name" "${obs:-—}" "$tag"
    BLOCKED=$((BLOCKED + 1)); continue
  fi

  if [ "$rc" = 0 ]; then
    printf '  \033[32mPASS\033[0m  %-30s %s%s\n' "$name" "${obs:-—}" "$tag"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %-30s %s%s\n' "$name" "${obs:-—}" "$tag"
    printf '%s\n' "$out" | grep -v '^BEOBACHTET:' | sed 's/^/        /'
    FAIL=$((FAIL + 1)); FAILED_CASES="$FAILED_CASES $name"
  fi
done

[ "$LIST" = 1 ] && exit 0

printf '\n%s\n' "────────────────────────────────────────────────────────────────"
printf 'bestanden %d · durchgefallen %d · blockiert %d · uebersprungen %d\n' "$PASS" "$FAIL" "$BLOCKED" "$SKIP"
[ "$FAIL" = 0 ] || printf 'durchgefallen:%s\n' "$FAILED_CASES"
[ "$BLOCKED" = 0 ] || printf 'blockiert: der Host konnte nicht antworten. Kein Urteil ueber diese Faelle — erneut laufen lassen.\n'

# 0 = alles gruen · 1 = echter Fehlschlag · 2 = kein Fehlschlag, aber blockierte Faelle
if [ "$FAIL" != 0 ]; then exit 1
elif [ "$BLOCKED" != 0 ]; then exit 2
else exit 0
fi
