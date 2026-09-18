#!/usr/bin/env bash
CASE_DESC="no file of the template names the project it came from"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# The reference this kit grew out of must not show through anywhere.
TERMS="AWAVE awave Android-spezifisch Gradle gradle Firebase firebase Kotlin ExoPlayer Hilt Roborazzi ktlint detekt awave-ops"
hits=""
for w in $TERMS; do
  # This file carries the word list itself and is therefore excluded.
  hits="$(grep -rl --exclude-dir=.git --exclude-dir=fixtures --exclude="$(basename "$0")" -- "$w" "$KIT_ROOT" 2>/dev/null | tr '\n' ' ')"
  [ -n "$hits" ] && hits="$hits '$w' in $hits;"
done

observe "${hits:-no project knowledge in the template}"
echo "OBSERVED: $OBSERVED"
[ -z "$hits" ]
