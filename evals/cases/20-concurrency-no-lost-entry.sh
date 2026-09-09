#!/usr/bin/env bash
CASE_DESC="N Sessions schreiben gleichzeitig, kein Chat-Eintrag geht verloren"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

ROLES="product-owner engineer-a engineer-b qa-ruthless simplicity-reviewer security-engineer acceptance-tester merge-gate watchdog"
PRO_ROLLE=5

for r in $ROLES; do
  (
    for i in $(seq 1 $PRO_ROLLE); do
      KIT_ROLE="$r" "$BIN/say.sh" "#$i · eintrag $i von $r" <<EOF > /dev/null 2>&1
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
echo "BEOBACHTET: $OBSERVED"
[ "$in_dateien" = "$erwartet" ] && [ "$im_index" = "$erwartet" ]
