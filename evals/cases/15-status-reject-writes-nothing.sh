#!/usr/bin/env bash
CASE_DESC="eine abgelehnte Transition schreibt nichts: kein Label, kein Board, kein Kommentar"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
cat >> "$KIT_ENV_FILE" <<'ENV'
KIT_BOARD="github-project"
ENV
printf 'KIT_PROJECT_ID="P"\nKIT_STATUS_FIELD_ID="F"\n' > "$KIT_BOARD_ENV_FILE"
for k in BACKLOG PLANNED IN_PROGRESS RFR IN_REVIEW RFT IN_TESTING DONE; do echo "KIT_OPTION_$k=\"opt-$k\"" >> "$KIT_BOARD_ENV_FILE"; done
sandbox_issue 9 '{"labels":["status:in-progress","owner:engineer-a"],"pr":{"number":90,"head":"cafecafe99","comments":[]}}'

snap() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["9"], sort_keys=True))' "$SANDBOX/issues.json"; }
vorher="$(snap)"; fehler=""

KIT_ROLE=engineer-b "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 && fehler="$fehler fremder-Besitz-durch"
KIT_ROLE=qa-ruthless "$BIN/status.sh" 9 rft x > /dev/null 2>&1 && fehler="$fehler Kante-durch"
KIT_ROLE=watchdog "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 && fehler="$fehler falsche-Rolle-durch"
nach_ablehnung="$(snap)"
[ "$vorher" = "$nach_ablehnung" ] || fehler="$fehler Zustand-veraendert"

# Board schlaegt fehl: Label darf sich NICHT aendern.
KIT_FAKE_BOARD_FAIL=1 KIT_ROLE=engineer-a "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 && fehler="$fehler Board-Fehler-ignoriert"
nach_boardfehler="$(sandbox_labels 9)"
[ "$nach_boardfehler" = "owner:engineer-a status:in-progress" ] || fehler="$fehler Label-trotz-Boardfehler='$nach_boardfehler'"

# Gegenprobe: ohne Fehler setzt dieselbe Transition Board UND Label.
KIT_ROLE=engineer-a "$BIN/status.sh" 9 rfr x > /dev/null 2>&1 || fehler="$fehler Gegenprobe-gescheitert"
board="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["9"].get("board","-"))' "$SANDBOX/issues.json")"
[ "$board" = "opt-RFR" ] || fehler="$fehler board='$board'"

observe "3 Ablehnungen, Zustand byte-gleich: $([ "$vorher" = "$nach_ablehnung" ] && echo ja || echo NEIN) · Board-Fehler → Labels '$nach_boardfehler' · Gegenprobe → board=$board, labels '$(sandbox_labels 9)'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
