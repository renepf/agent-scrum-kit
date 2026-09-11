#!/usr/bin/env bash
CASE_DESC="falsche Fakten werden geloescht, nicht ergaenzt; geteilte Fakten aendert und loescht nur der Autor"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
fehler=""
KIT_ROLE=security-engineer "$BIN/brain.sh" share token-im-log "Tokens landen im Debug-Log" <<<'Gemessen 2026-09-10.' > /dev/null || fehler="$fehler share"
o1="$(KIT_ROLE=engineer-b "$BIN/brain.sh" share token-im-log "Tokens landen nicht mehr im Log" <<<'x' 2>&1)"
case "$o1" in *"gehoert security-engineer"*) ;; *) fehler="$fehler fremdes-Ueberschreiben-durch" ;; esac
o2="$(KIT_ROLE=engineer-b "$BIN/brain.sh" forget token-im-log --shared 2>&1)"
case "$o2" in *"nur der Autor"*) ;; *) fehler="$fehler fremdes-Loeschen-durch" ;; esac
KIT_ROLE=security-engineer "$BIN/brain.sh" forget token-im-log --shared > /dev/null 2>&1 || fehler="$fehler Autor-darf-nicht-loeschen"
[ ! -f "$SANDBOX/memory/_shared/facts/token-im-log.md" ] || fehler="$fehler Datei-noch-da"
grep -q 'token-im-log' "$SANDBOX/memory/_shared/INDEX.md" && fehler="$fehler Index-zeigt-geloeschten-Fakt"
o3="$(KIT_ROLE=security-engineer "$BIN/brain.sh" forget token-im-log --shared 2>&1)"
case "$o3" in *"gibt es nicht"*) ;; *) fehler="$fehler zweites-Loeschen-meldet-Erfolg" ;; esac
observe "fremd ueberschreiben → abgelehnt · fremd loeschen → abgelehnt · Autor loescht → Datei und Indexzeile weg · erneut loeschen → 'gibt es nicht'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
