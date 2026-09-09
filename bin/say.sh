#!/usr/bin/env bash
# Einen Chat-Eintrag in die EIGENE Rollendatei anhaengen und neu indizieren.
#
#   bin/say.sh "#712 · PR #755 gruen, 14 Tests" <<'EOF'
#   Offen: Netzabbruch mitten im Aufruf → @qa-ruthless bitte pruefen.
#   EOF
#
# Append-only. Bestehende Zeilen werden nie geaendert — der Index verweist auf
# feste Zeilennummern, die fuer immer gueltig bleiben muessen.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ $# -ge 1 ] || die "Aufruf: bin/say.sh \"<betreff>\" < <rumpf>"

SPRINT="$(sprint_dir)"
R="$(role)"
FILE="$SPRINT/chat/$R.md"
SUBJECT="$1"

# Ticketnummer vom Betreff abtrennen, wenn sie vorn steht.
TICKET="-"
case "$SUBJECT" in
  \#[0-9]*) TICKET="${SUBJECT%% *}"; SUBJECT="${SUBJECT#* }" ;;
esac
SUBJECT="${SUBJECT#· }"

mkdir -p "$SPRINT/chat"
BODY="$(cat)"

append_entry() {
  [ -f "$FILE" ] || printf '# chat · %s\n\nAppend-only. Bestehende Zeilen werden nie editiert —\nder Index verweist auf feste Zeilennummern.\n' "$R" > "$FILE"
  {
    printf '\n## %s · %s · %s · %s\n' "$(now)" "$R" "$TICKET" "$SUBJECT"
    printf '%s\n' "$BODY"
  } >> "$FILE"
}

# Sperre je Datei: zwei Sessions derselben Rolle wuerden sonst eine Zeile verlieren.
with_lock "$FILE.lock" append_entry

"$(dirname "${BASH_SOURCE[0]}")/reindex.sh" > /dev/null
echo "notiert in chat/$R.md:$(wc -l < "$FILE" | tr -d ' ')"
