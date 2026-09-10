#!/usr/bin/env bash
CASE_DESC="der Adapter raet die Session-ID nie aus der juengsten Transkriptdatei"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

FAKEHOME="$(mktemp -d)"; trap 'rm -rf "$FAKEHOME"' EXIT
mkdir -p "$FAKEHOME/.claude/projects/p"
touch "$FAKEHOME/.claude/projects/p/fremde-session.jsonl"   # juengste Datei gehoert jemand anderem
A="$KIT_ROOT/adapters/claude-code/session-id.sh"

ohne="$(HOME="$FAKEHOME" KIT_SESSION_ID= CLAUDE_CODE_SESSION_ID= "$A" 2>/dev/null)"; rc_ohne=$?
mit="$(HOME="$FAKEHOME" KIT_SESSION_ID= CLAUDE_CODE_SESSION_ID=eigene-session "$A" 2>/dev/null)"; rc_mit=$?

fehler=""
[ "$rc_ohne" != 0 ] || fehler="$fehler ohne-Variable-kein-Abbruch"
[ "$ohne" != "fremde-session" ] || fehler="$fehler hat-fremde-Session-geraten"
[ "$mit" = "eigene-session" ] || fehler="$fehler mit-Variable='$mit'"

observe "ohne Variable: Exit $rc_ohne, Ausgabe '${ohne}' · mit CLAUDE_CODE_SESSION_ID: '$mit' · juengste fremde Datei ignoriert${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
