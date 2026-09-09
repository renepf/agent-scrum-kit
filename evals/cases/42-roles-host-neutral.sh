#!/usr/bin/env bash
CASE_DESC="Jobbeschreibungen enthalten kein Host-Vokabular"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# Wortliste bewusst eng: Produktnamen von Hosts, nicht allgemeine Begriffe.
treffer=""
for w in claude Claude codex Codex cursor Cursor "Hermes" "PI Code" "/clear" "/compact" "Subagent-Tool" "Task-Tool"; do
  hits="$(grep -rl -- "$w" "$KIT_ROOT"/roles/*.md 2>/dev/null | tr '\n' ' ')"
  [ -n "$hits" ] && treffer="$treffer '$w' in $hits;"
done

observe "${treffer:-kein Host-Vokabular in roles/}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$treffer" ]
