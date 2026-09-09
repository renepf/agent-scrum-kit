#!/usr/bin/env bash
CASE_DESC="fehlendes Transkript ergibt UNKNOWN, nie eine 0 — und nennt die richtige Ursache"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

{
  printf '# roster\n\n| Zeit | Rolle | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | gibt-es-nicht | test-fixture |\n'
} > "$SPRINT/roster.md"

# Fall A: Adapter laeuft, findet diese eine Kennung nicht.
KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
a="$(grep '| engineer-a |' "$SPRINT/budget.md")"

# Fall B: Host kennt gar keine Transkripte (Adapter nicht ausfuehrbar).
chmod -x "$KIT_ROOT/adapters/test-fixture/transcript-path.sh"
KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1
b="$(grep '| engineer-a |' "$SPRINT/budget.md")"
chmod +x "$KIT_ROOT/adapters/test-fixture/transcript-path.sh"

fehler=""
case "$a" in *UNKNOWN*"nicht gefunden"*) ;; *) fehler="$fehler A='$a'" ;; esac
case "$b" in *UNKNOWN*"keine Transkripte"*Notbremse*) ;; *) fehler="$fehler B='$b'" ;; esac
case "$a$b" in *"| 0 |"*) fehler="$fehler Null-statt-UNKNOWN" ;; esac

observe "A: Session unbekannt → '$(echo "$a" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')' · B: Host ohne Transkripte → '$(echo "$b" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
