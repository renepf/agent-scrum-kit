#!/usr/bin/env bash
CASE_DESC="sub-headings inside the body of an entry do not enter the index"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

KIT_ROLE=product-owner "$BIN/say.sh" "#1 · Planung" <<'EOF' > /dev/null 2>&1
## The three questions I need your verdict on
1. erste
## Offene Punkte
- zweiter
EOF
KIT_ROLE=engineer-a "$BIN/say.sh" "#1 · answer" <<'EOF' > /dev/null 2>&1
ok
EOF

n="$(grep -c '^| [0-9]' "$SPRINT/INDEX.md")"
ghosts="$(grep -c 'The three questions\|Open points' "$SPRINT/INDEX.md" || true)"
observe "index entries $n (expected 2) · ghost entries from sub-headings $ghosts"
echo "OBSERVED: $OBSERVED"
[ "$n" = 2 ] && [ "$ghosts" = 0 ]
