#!/usr/bin/env bash
CASE_DESC="an @role mention reaches exactly that role, exactly once"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

KIT_ROLE=product-owner "$BIN/say.sh" "#4 · verdict" <<'EOF' > /dev/null 2>&1
@engineer-b please check the solution path.
EOF
KIT_ROLE=engineer-b "$BIN/say.sh" "#4 · a note of my own" <<'EOF' > /dev/null 2>&1
Note to self: @engineer-b later.
EOF

a1="$(KIT_ROLE=engineer-b "$BIN/tick.sh" 2>&1)"
a2="$(KIT_ROLE=engineer-b "$BIN/tick.sh" 2>&1)"
b1="$(KIT_ROLE=engineer-c "$BIN/tick.sh" 2>&1)"

count_of() { printf '%s' "$1" | sed -n '/addressed directly to you/,/──/p' | grep -c 'chat/' || true; }
n1="$(count_of "$a1")"; n2="$(count_of "$a2")"; nb="$(count_of "$b1")"
own="$(printf '%s' "$a1" | sed -n '/addressed directly to you/,$p' | grep -c 'chat/engineer-b.md' || true)"

observe "engineer-b tick1: $n1 mention (own file: $own) · tick2: $n2 · engineer-c: $nb"
echo "OBSERVED: $OBSERVED"
[ "$n1" = 1 ] && [ "$own" = 0 ] && [ "$n2" = 0 ] && [ "$nb" = 0 ]
