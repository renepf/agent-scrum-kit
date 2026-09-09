#!/usr/bin/env bash
# Baut sprints/<aktiv>/INDEX.md komplett neu aus allen chat/*.md.
# GENERIERT, nie von Hand editiert. Deterministisch: gleicher Input, gleiche Ausgabe.
# Atomar: erst temporaer schreiben, dann umbenennen — ein halb geschriebener Index
# kann nie gelesen werden.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPRINT="$(sprint_dir)"
cd "$SPRINT"

{
  echo "# INDEX — $(basename "$SPRINT")"
  echo
  echo "GENERIERT von bin/reindex.sh. Nicht von Hand editieren."
  echo
  echo "| Zeit | Rolle | Ticket | Betreff | Quelle |"
  echo "|---|---|---|---|---|"
  # Kopfzeilen haben die Form:  ## <datum> <zeit> · <rolle> · <ticket> · <betreff>
  grep -Hn '^## ' chat/*.md 2>/dev/null \
    | sed 's/^\(chat\/[^:]*\):\([0-9]*\):## /\1\t\2\t/' \
    | awk -F'\t' '{
        n = split($3, f, / · /)
        zeit = f[1]; rolle = (n>1 ? f[2] : "?"); ticket = (n>2 ? f[3] : "-")
        betreff = ""
        for (i = 4; i <= n; i++) betreff = betreff (i>4 ? " · " : "") f[i]
        if (betreff == "") betreff = "-"
        printf "%s\t%s\t%09d\t| %s | %s | %s | %s | %s:%s |\n", zeit, $1, $2, zeit, rolle, ticket, betreff, $1, $2
      }' \
    | sort \
    | cut -f4-
} | atomic_write "$SPRINT/INDEX.md"

echo "INDEX.md neu gebaut: $(grep -c '^| [0-9]' "$SPRINT/INDEX.md" || true) Eintraege"
