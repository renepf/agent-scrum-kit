#!/usr/bin/env bash
CASE_DESC="N sessions write at the same time, no chat entry is lost"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

# The whole cast at once — seven roles since the cut of 2026-09-28. The point is the count that
# comes out at the end, not how many roles there are: not one entry may be lost.
ROLES="product-owner requirements-engineer engineer-a engineer-b engineer-c watchdog kit-maintainer"
PRO_ROLLE=5

for r in $ROLES; do
  (
    for i in $(seq 1 $PRO_ROLLE); do
      KIT_ROLE="$r" "$BIN/say.sh" "#$i · entry $i from $r" <<EOF > /dev/null 2>&1
rumpf $r $i
EOF
    done
  ) &
done
wait

erwartet=$(( $(echo "$ROLES" | wc -w | tr -d ' ') * PRO_ROLLE ))
in_dateien="$(grep -h -c '^## ' "$SPRINT"/chat/*.md | paste -sd+ - | bc)"
"$BIN/reindex.sh" > /dev/null
im_index="$(grep -c '^| [0-9]' "$SPRINT/INDEX.md")"

observe "erwartet $erwartet · in Chatdateien $in_dateien · im Index $im_index"
echo "OBSERVED: $OBSERVED"
[ "$in_dateien" = "$erwartet" ] && [ "$im_index" = "$erwartet" ]
