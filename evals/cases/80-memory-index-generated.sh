#!/usr/bin/env bash
CASE_DESC="der Gedaechtnis-Index ist generiert: eine Zeile je Eintrag, deterministisch, offene [[Verweise]] sichtbar"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
export KIT_ROLE=qa-ruthless
TYPE=feedback "$BIN/brain.sh" note mutation-je-zusicherung "gruen nach Entfernen einer Schutzbedingung heisst Test fehlt" <<'EOF' > /dev/null
Eine Mutation je Zusicherung. Siehe [[leerer-startzustand]] und [[gibt-es-noch-nicht]].
EOF
TYPE=project "$BIN/brain.sh" note leerer-startzustand "Test mit leerem Zustand sieht den echten Pfad oft nicht" <<'EOF' > /dev/null
Gemessen 2026-09-10.
EOF
I="$SANDBOX/memory/qa-ruthless/INDEX.md"
zeilen="$(grep -c '^| \[facts/' "$I")"
h1="$(shasum "$I" | cut -d' ' -f1)"
KIT_ROLE=qa-ruthless "$BIN/brain.sh" index > /dev/null
h2="$(shasum "$I" | cut -d' ' -f1)"
offen="$(grep -c '`\[\[gibt-es-noch-nicht\]\]`' "$I" || true)"
aufgeloest="$(grep -c '`\[\[leerer-startzustand\]\]`' "$I" || true)"
kopf="$(grep -c 'GENERIERT von bin/brain.sh' "$I")"
fehler=""
[ "$zeilen" = 2 ] || fehler="$fehler zeilen=$zeilen"
[ "$h1" = "$h2" ] || fehler="$fehler nicht-deterministisch"
[ "$offen" = 1 ] || fehler="$fehler offener-Verweis-nicht-gelistet"
[ "$aufgeloest" = 0 ] || fehler="$fehler aufgeloester-Verweis-als-offen-gelistet"
[ "$kopf" = 1 ] || fehler="$fehler kein-GENERIERT-Kopf"
observe "2 Fakten → $zeilen Indexzeilen · Neubau identisch: $([ "$h1" = "$h2" ] && echo ja || echo NEIN) · offen: [[gibt-es-noch-nicht]] ($offen), nicht offen: [[leerer-startzustand]]${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
