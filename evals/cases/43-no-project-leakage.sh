#!/usr/bin/env bash
CASE_DESC="no file of the template names the project it came from"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# The reference this kit grew out of must not show through anywhere.
TERMS="AWAVE awave Android-spezifisch Gradle gradle Firebase firebase Kotlin ExoPlayer Hilt Roborazzi ktlint detekt awave-ops"
# One collector, one per-term variable. Assigning the collector inside the loop would throw away
# every earlier term: only the LAST matching term would survive, and a run where the last term does
# not match would report nothing at all while the kit still leaks.
hits=""
for w in $TERMS; do
  # This file carries the word list itself and is therefore excluded.
  files="$(grep -rl --exclude-dir=.git --exclude-dir=fixtures --exclude="$(basename "$0")" -- "$w" "$KIT_ROOT" 2>/dev/null \
           | sed "s#^$KIT_ROOT/##" | sort)"
  [ -z "$files" ] && continue
  n="$(printf '%s\n' "$files" | grep -c .)"
  # The first three paths are enough to find it; the count says how big the leak is.
  hits="$hits '$w' in $n file(s): $(printf '%s\n' "$files" | head -3 | tr '\n' ' ')$( [ "$n" -gt 3 ] && printf '... ' );"
done

observe "${hits:-no project knowledge in the template}"
echo "OBSERVED: $OBSERVED"
[ -z "$hits" ]
