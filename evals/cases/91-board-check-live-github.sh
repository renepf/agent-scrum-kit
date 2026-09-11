#!/usr/bin/env bash
CASE_DESC="das konfigurierte GitHub Project bildet das Statusmodell ab (echter gh-Aufruf, liest nur)"
CASE_KIND="gh"
CASE_HOST="github"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Liest kit.env des Kits selbst, nicht den Sandkasten: geprueft wird DEIN Board.
unset KIT_ENV_FILE KIT_BOARD_ENV_FILE
[ -f "$KIT_ROOT/kit.env" ] || { echo "BEOBACHTET: BLOCKIERT — kit.env fehlt"; exit 3; }
grep -q '^KIT_BOARD="github-project"' "$KIT_ROOT/kit.env" || { echo "BEOBACHTET: BLOCKIERT — KIT_BOARD ist nicht github-project"; exit 3; }
out="$("$BIN/board-check.sh" 2>&1)"; rc=$?
case "$out" in *"Preflight fehlgeschlagen"*|*"nicht lesbar"*) echo "BEOBACHTET: BLOCKIERT — $(echo "$out" | tail -1)"; exit 3 ;; esac
ok="$(printf '%s' "$out" | grep -c '^OK' || true)"; fail="$(printf '%s' "$out" | grep -c '^FAIL' || true)"
observe "$(printf '%s' "$out" | tail -1) · $ok OK, $fail FAIL"
printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/  /'
echo "BEOBACHTET: $OBSERVED"
[ "$rc" = 0 ]
