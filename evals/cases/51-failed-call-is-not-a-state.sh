#!/usr/bin/env bash
CASE_DESC="ein fehlgeschlagener Werkzeugaufruf wird nie als Zustand ausgelegt"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_ticket 5 planned
export KIT_ROLE=engineer-a

vorher="$("$BIN/tickets.sh" labels 5 | tr '\n' ' ')"

# Das Backend faellt aus: preflight muss scheitern und status.sh muss abbrechen,
# ohne das Label anzufassen und ohne "war wohl schon erledigt" zu schliessen.
cat > "$SANDBOX/kaputt.env" <<ENV
$(cat "$SANDBOX/kit.env")
KIT_ISSUE_BACKEND="gh"
KIT_REPO="eval/gibt-es-nicht"
ENV
export PATH="$SANDBOX/fakebin:$PATH"
mkdir -p "$SANDBOX/fakebin"
printf '#!/usr/bin/env bash\necho "HTTP 503: service unavailable" >&2\nexit 1\n' > "$SANDBOX/fakebin/gh"
chmod +x "$SANDBOX/fakebin/gh"

out="$(KIT_ENV_FILE="$SANDBOX/kaputt.env" "$BIN/status.sh" 5 in-progress "versuch" 2>&1)"; rc=$?
nachher="$(KIT_ENV_FILE="$SANDBOX/kit.env" "$BIN/tickets.sh" labels 5 | tr '\n' ' ')"

fehler=""
[ "$rc" != 0 ] || fehler="$fehler status.sh-hat-nicht-abgebrochen"
[ "$vorher" = "$nachher" ] || fehler="$fehler Label-geaendert($vorher->$nachher)"
case "$out" in *[Ff]ehl*) ;; *) fehler="$fehler keine-Fehlermeldung" ;; esac

observe "Exitcode $rc · Label vor '$vorher' nach '$nachher' · Meldung: $(echo "$out" | tail -1 | cut -c1-60)${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
