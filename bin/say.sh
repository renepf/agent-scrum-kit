#!/usr/bin/env bash
# Append a chat entry to your OWN role file and reindex.
#
#   bin/say.sh "#712 · PR #755 green, 14 tests" <<'EOF'
#   Open: network drop in the middle of the call → @qa-ruthless please check.
#   EOF
#
# Append-only. Existing lines are never changed — the index points at
# fixed line numbers that must stay valid forever.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ $# -ge 1 ] || die "usage: bin/say.sh \"<subject>\" < <body>"

SPRINT="$(sprint_dir)"
R="$(role)"
FILE="$SPRINT/chat/$R.md"
SUBJECT="$1"

# Split the ticket number off the subject when it comes first.
TICKET="-"
case "$SUBJECT" in
  \#[0-9]*) TICKET="${SUBJECT%% *}"; SUBJECT="${SUBJECT#* }" ;;
esac
SUBJECT="${SUBJECT#· }"

mkdir -p "$SPRINT/chat"
BODY="$(cat)"

append_entry() {
  [ -f "$FILE" ] || printf '# chat · %s\n\nAppend-only. Existing lines are never edited —\nthe index points at fixed line numbers.\n' "$R" > "$FILE"
  {
    printf '\n## %s · %s · %s · %s\n' "$(now)" "$R" "$TICKET" "$SUBJECT"
    printf '%s\n' "$BODY"
  } >> "$FILE"
}

# One lock per file: two sessions of the same role would otherwise lose a line.
with_lock "$FILE.lock" append_entry

"$(dirname "${BASH_SOURCE[0]}")/reindex.sh" > /dev/null
echo "noted in chat/$R.md:$(wc -l < "$FILE" | tr -d ' ')"
