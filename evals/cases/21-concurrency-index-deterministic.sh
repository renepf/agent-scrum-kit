#!/usr/bin/env bash
CASE_DESC="der Index ist nach gleichzeitigem Schreiben deterministisch und vollstaendig"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

for r in engineer-a engineer-b qa-ruthless security-engineer; do
  ( for i in 1 2 3 4 5 6; do
      KIT_ROLE="$r" "$BIN/say.sh" "#$i · $r $i" <<EOF > /dev/null 2>&1
rumpf
EOF
    done ) &
done
wait

# Zehn Neubauten muessen zehnmal dieselbe Datei ergeben.
h1="$("$BIN/reindex.sh" > /dev/null; shasum "$SPRINT/INDEX.md" | cut -d' ' -f1)"
gleich=1
for _ in $(seq 1 9); do
  h="$("$BIN/reindex.sh" > /dev/null; shasum "$SPRINT/INDEX.md" | cut -d' ' -f1)"
  [ "$h" = "$h1" ] || gleich=0
done

# Jede Quellzeile muss auf eine echte Ueberschrift zeigen (append-only, Zeilen bleiben gueltig).
zeiger_ok=1
while IFS= read -r ref; do
  f="${ref%%:*}"; l="${ref##*:}"
  case "$(sed -n "${l}p" "$SPRINT/$f")" in "## "*) ;; *) zeiger_ok=0 ;; esac
done < <(grep -o 'chat/[a-z-]*\.md:[0-9]*' "$SPRINT/INDEX.md")

observe "10 Neubauten identisch: $([ $gleich = 1 ] && echo ja || echo NEIN) · alle datei:zeile-Zeiger treffen eine Ueberschrift: $([ $zeiger_ok = 1 ] && echo ja || echo NEIN) · sha $h1"
echo "BEOBACHTET: $OBSERVED"
[ "$gleich" = 1 ] && [ "$zeiger_ok" = 1 ]
