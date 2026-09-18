#!/usr/bin/env bash
CASE_DESC="after simultaneous writing the index is deterministic and complete"
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

# Ten rebuilds must give the same file ten times.
h1="$("$BIN/reindex.sh" > /dev/null; shasum "$SPRINT/INDEX.md" | cut -d' ' -f1)"
same=1
for _ in $(seq 1 9); do
  h="$("$BIN/reindex.sh" > /dev/null; shasum "$SPRINT/INDEX.md" | cut -d' ' -f1)"
  [ "$h" = "$h1" ] || same=0
done

# Every source line must point at a real heading (append-only, the lines stay valid).
pointers_ok=1
while IFS= read -r ref; do
  f="${ref%%:*}"; l="${ref##*:}"
  case "$(sed -n "${l}p" "$SPRINT/$f")" in "## "*) ;; *) pointers_ok=0 ;; esac
done < <(grep -o 'chat/[a-z-]*\.md:[0-9]*' "$SPRINT/INDEX.md")

observe "10 rebuilds identical: $([ $same = 1 ] && echo yes || echo NO) · every file:line pointer hits a heading: $([ $pointers_ok = 1 ] && echo yes || echo NO) · sha $h1"
echo "OBSERVED: $OBSERVED"
[ "$same" = 1 ] && [ "$pointers_ok" = 1 ]
