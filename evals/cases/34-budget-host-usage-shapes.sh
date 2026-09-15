#!/usr/bin/env bash
CASE_DESC="qwen and pi transcripts give the exact context value; a transcript without a usage record is UNKNOWN, never 0"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"

# Record shapes measured 2026-09-15 against Ollama qwen2.5-coder:14b:
#   qwen 0.23.4  chats/<id>.jsonl  usageMetadata.promptTokenCount already contains cachedContentTokenCount
#                (20228 prompt + 15879 cached would exceed the 32768 context Ollama served)
#   pi 0.85.1    sessions/…_<id>.jsonl  message.usage.input excludes cacheRead and cacheWrite (pi docs/models.md)
# sess-qwen: turns 20228 and 30000 → 30000 (not 30100 with the cache, not the sum 50228)
# sess-pi:   turns 1713+5+0 and 1000+2000+10 → 3010
{
  printf '# roster\n\n| Zeit | Rolle | Session-ID | Host |\n|---|---|---|---|\n'
  printf '| 2026-01-01 00:00 | engineer-a | sess-qwen | test-fixture |\n'
  printf '| 2026-01-01 00:00 | engineer-b | sess-pi | test-fixture |\n'
  printf '| 2026-01-01 00:00 | qa-ruthless | sess-nousage | test-fixture |\n'
} > "$SPRINT/roster.md"

KIT_ROLE=watchdog "$BIN/budget.sh" > /dev/null 2>&1

col() { grep "| $1 |" "$SPRINT/budget.md" | awk -F'|' -v c="$2" '{gsub(/^ +| +$/,"",$c); print $c}'; }
q="$(col engineer-a 4)"; qo="$(col engineer-a 5)"
p="$(col engineer-b 4)"; po="$(col engineer-b 5)"
n="$(col qa-ruthless 4)"; nl="$(col qa-ruthless 6)"

fehler=""
[ "$q" = "30 000" ] || fehler="$fehler qwen-context='$q'"
[ "$qo" = "43" ] || fehler="$fehler qwen-output='$qo'"
[ "$p" = "3 010" ] || fehler="$fehler pi-context='$p'"
[ "$po" = "23" ] || fehler="$fehler pi-output='$po'"
[ "$n" = "UNKNOWN" ] || fehler="$fehler no-usage-context='$n'"
case "$nl" in *"no usage record"*) ;; *) fehler="$fehler no-usage-reason='$nl'" ;; esac

observe "qwen $q / out $qo (expected 30 000 / 43) · pi $p / out $po (expected 3 010 / 23) · no usage: $n, '$nl'${fehler:+ · FEHLER:$fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
