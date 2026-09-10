#!/usr/bin/env bash
CASE_DESC="eine frische Kopie ist nach Ausfuellen der Konfiguration lauffaehig"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

ZIEL="$(mktemp -d "${TMPDIR:-/tmp}/kit-copy.XXXXXX")"
trap 'rm -rf "$ZIEL"' EXIT
# So, wie ein fremdes Projekt das Kit kopieren wuerde: ohne .git, ohne kit.env.
( cd "$KIT_ROOT" && tar --exclude .git --exclude kit.env --exclude 'sprints' -cf - . ) | ( cd "$ZIEL" && tar -xf - )

fehler=""

# 1. Ohne kit.env laeuft nichts, und die Meldung sagt, was zu tun ist.
out="$(cd "$ZIEL" && KIT_ENV_FILE="$ZIEL/kit.env" bin/preflight.sh 2>&1)"; rc=$?
[ "$rc" != 0 ] || fehler="$fehler laeuft-ohne-kit.env"
case "$out" in *"kit.env.example"*) ;; *) fehler="$fehler Meldung-nennt-den-naechsten-Schritt-nicht" ;; esac

# 2. Konfiguration ausfuellen — genau der Weg aus dem README.
cp "$ZIEL/kit.env.example" "$ZIEL/kit.env"
python3 - "$ZIEL" <<'PY'
import sys, pathlib
z = pathlib.Path(sys.argv[1])
p = z / "kit.env"
t = p.read_text()
t = t.replace('KIT_REPO="UNKNOWN — beim Owner erfragen, z.B. meine-org/mein-repo"', 'KIT_REPO="fremd/projekt"')
t = t.replace('KIT_WORKTREE_ROOT="$HOME/Developer/mein-projekt"', f'KIT_WORKTREE_ROOT="{z}"')
t = t.replace('KIT_ISSUE_BACKEND="gh"', 'KIT_ISSUE_BACKEND="file"')
t += f'\nKIT_SPRINTS_DIR="{z}/sprints"\n'
p.write_text(t)
PY

# 3. Der volle Weg: preflight, Sprint, Ticket, Statuswechsel, Chat, Index.
( cd "$ZIEL" && export KIT_ROLE=product-owner KIT_SESSION_ID=kopie-test
  bin/preflight.sh > /dev/null 2>&1 || exit 11
  bin/tickets.sh add-label 1 status:backlog > /dev/null 2>&1 || exit 12
  bin/sprint-new.sh erster-sprint 1 > /dev/null 2>&1 || exit 13
  bin/status.sh 1 planned "los" > /dev/null 2>&1 || exit 14
  bin/say.sh "#1 · Kopie laeuft" <<'EOF' > /dev/null 2>&1 || exit 15
Beleg aus der frischen Kopie.
EOF
) ; schritt=$?
[ "$schritt" = 0 ] || fehler="$fehler abgebrochen-bei-Schritt-$schritt"

eintraege="$(grep -c '^| [0-9]' "$ZIEL/sprints/$(cat "$ZIEL/sprints/CURRENT" 2>/dev/null)/INDEX.md" 2>/dev/null || echo 0)"
[ "$eintraege" -ge 2 ] || fehler="$fehler Index-hat-nur-$eintraege-Eintraege"

observe "ohne kit.env: Exit $rc mit Hinweis · nach Ausfuellen: preflight, Sprint, Statuswechsel, Chat, Index mit $eintraege Eintraegen${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
