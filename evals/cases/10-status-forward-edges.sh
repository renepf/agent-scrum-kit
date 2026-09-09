#!/usr/bin/env bash
CASE_DESC="jede erlaubte Kante der Vorwaertsschleife funktioniert"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_ticket 1 open

export KIT_ROLE=product-owner
ok=0; bad=""
for step in "planned:product-owner" "in-progress:engineer-a" "rfr:engineer-a" \
            "in-review:qa-ruthless" "rft:qa-ruthless" "closed:product-owner"; do
  st="${step%%:*}"; who="${step##*:}"
  if KIT_ROLE="$who" "$BIN/status.sh" 1 "$st" "eval" > /dev/null 2>&1; then
    ok=$((ok + 1))
  else
    bad="$bad $st"
  fi
done
observe "$ok/6 Kanten akzeptiert${bad:+, abgelehnt:$bad}"
echo "BEOBACHTET: $OBSERVED"
[ "$ok" = 6 ]
