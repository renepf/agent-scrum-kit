#!/usr/bin/env bash
CASE_DESC="keine Datei des Templates nennt das Ursprungsprojekt"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# Die Referenz, aus der dieses Kit hervorging, darf nirgends durchschlagen.
BEGRIFFE="AWAVE awave Android-spezifisch Gradle gradle Firebase firebase Kotlin ExoPlayer Hilt Roborazzi ktlint detekt awave-ops"
treffer=""
for w in $BEGRIFFE; do
  # Diese Datei traegt die Wortliste selbst und ist deshalb ausgenommen.
  hits="$(grep -rl --exclude-dir=.git --exclude-dir=fixtures --exclude="$(basename "$0")" -- "$w" "$KIT_ROOT" 2>/dev/null | tr '\n' ' ')"
  [ -n "$hits" ] && treffer="$treffer '$w' in $hits;"
done

observe "${treffer:-kein Projektwissen im Template}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$treffer" ]
