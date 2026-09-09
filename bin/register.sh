#!/usr/bin/env bash
# Rolle + Session-ID in roster.md eintragen. Beim Start jeder Session und nach jedem Reset.
#
#   export KIT_ROLE=engineer-a
#   bin/register.sh                 # Session-ID vom Host-Adapter
#   bin/register.sh <session-id>    # oder explizit
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPRINT="$(sprint_dir)"
R="$(role)"
SID="${1:-$(session_id)}"
ROSTER="$SPRINT/roster.md"

write_roster() {
  local head body
  head='| Zeit | Rolle | Session-ID | Host |'
  body="$( { [ -f "$ROSTER" ] && grep '^| 2' "$ROSTER" | grep -v "^| .* | $R | " || true; } )"
  {
    printf '# roster · %s\n\n' "$(basename "$SPRINT")"
    printf 'GENERIERT von bin/register.sh. Eine Zeile je Rolle, juengster Eintrag gilt.\n\n'
    printf '%s\n|---|---|---|---|\n' "$head"
    [ -n "$body" ] && printf '%s\n' "$body"
    printf '| %s | %s | %s | %s |\n' "$(now)" "$R" "$SID" "$KIT_HOST"
  } | atomic_write "$ROSTER"
}

# Sperre: neun Sessions registrieren sich beim Start fast gleichzeitig.
with_lock "$ROSTER.lock" write_roster

echo "$R registriert · session $SID · host $KIT_HOST"
