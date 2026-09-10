#!/usr/bin/env bash
CASE_DESC="Zwischenueberschriften im Rumpf eines Eintrags landen nicht im Index"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

KIT_ROLE=product-owner "$BIN/say.sh" "#1 · Planung" <<'EOF' > /dev/null 2>&1
## Die drei Fragen, zu denen ich euer Urteil brauche
1. erste
## Offene Punkte
- zweiter
EOF
KIT_ROLE=engineer-a "$BIN/say.sh" "#1 · Antwort" <<'EOF' > /dev/null 2>&1
ok
EOF

n="$(grep -c '^| [0-9]' "$SPRINT/INDEX.md")"
geister="$(grep -c 'Die drei Fragen\|Offene Punkte' "$SPRINT/INDEX.md" || true)"
observe "Index-Eintraege $n (erwartet 2) · Geistereintraege aus Zwischenueberschriften $geister"
echo "BEOBACHTET: $OBSERVED"
[ "$n" = 2 ] && [ "$geister" = 0 ]
