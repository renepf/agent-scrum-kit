#!/usr/bin/env bash
# Eval suite. One command, per case passed/failed with the observed value.
#
#   evals/run.sh                 # every case except the live ones
#   evals/run.sh --live          # plus the cases with a real model call
#   evals/run.sh --gh            # plus the cases with real GitHub access (read only)
#   evals/run.sh --net           # plus the cases with package downloads (MCP handshakes)
#   evals/run.sh --case <name>   # exactly one case
#   evals/run.sh --list          # list only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE=0; GH=0; NET=0; ONLY=""; LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE=1 ;;
    --gh) GH=1 ;;
    --net) NET=1 ;;
    --case) ONLY="${2:-}"; shift ;;
    --list) LIST=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

PASS=0; FAIL=0; SKIP=0; BLOCKED=0
FAILED_CASES=""

printf '%s\n' "── agent-scrum-kit · eval suite ────────────────────────────────"
printf 'live cases: %s · gh cases: %s\n\n' "$([ "$LIVE" = 1 ] && echo "on" || echo "off (--live)")" "$([ "$GH" = 1 ] && echo "on" || echo "off (--gh)")"; printf 'net cases: %s\n\n' "$([ "$NET" = 1 ] && echo "on" || echo "off (--net)")"

for f in "$HERE"/cases/*.sh; do
  name="$(basename "$f" .sh)"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || [ "$ONLY" = "${name#*-}" ] || continue

  # Read the meta without executing.
  DESC="$(grep -m1 '^CASE_DESC=' "$f" | cut -d= -f2- | tr -d '"')"
  KIND="$(grep -m1 '^CASE_KIND=' "$f" | cut -d= -f2- | tr -d '"')"
  HOST="$(grep -m1 '^CASE_HOST=' "$f" | cut -d= -f2- | tr -d '"')"

  if [ "$LIST" = 1 ]; then
    printf '%-34s %-8s %s\n' "$name" "$KIND" "$DESC"
    continue
  fi

  if [ "$KIND" = "net" ] && [ "$NET" != 1 ]; then
    printf '  \033[33mSKIP\033[0m  %-30s %s\n' "$name" "needs --net"
    SKIP=$((SKIP + 1)); continue
  fi
  if [ "$KIND" = "gh" ] && [ "$GH" != 1 ]; then
    printf '  \033[33mSKIP\033[0m  %-30s %s\n' "$name" "needs --gh"
    SKIP=$((SKIP + 1)); continue
  fi
  if [ "$KIND" = "live" ] && [ "$LIVE" != 1 ]; then
    printf '  \033[33mSKIP\033[0m  %-30s %s\n' "$name" "needs --live"
    SKIP=$((SKIP + 1)); continue
  fi

  out="$(bash "$f" 2>&1)"; rc=$?
  obs="$(printf '%s' "$out" | grep '^OBSERVED:' | sed 's/^OBSERVED: //' | tr '\n' ' ')"
  tag=""
  [ -n "$HOST" ] && tag=" [host-bound: $HOST]"

  # Exit code 3 = the host could not answer (quota, network, empty answer).
  # That is a failure of the run, not a verdict about the role.
  if [ "$rc" = 3 ]; then
    printf '  \033[33mBLOCK\033[0m %-30s %s%s\n' "$name" "${obs:-—}" "$tag"
    BLOCKED=$((BLOCKED + 1)); continue
  fi

  if [ "$rc" = 0 ]; then
    printf '  \033[32mPASS\033[0m  %-30s %s%s\n' "$name" "${obs:-—}" "$tag"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %-30s %s%s\n' "$name" "${obs:-—}" "$tag"
    printf '%s\n' "$out" | grep -v '^OBSERVED:' | sed 's/^/        /'
    FAIL=$((FAIL + 1)); FAILED_CASES="$FAILED_CASES $name"
  fi
done

[ "$LIST" = 1 ] && exit 0

printf '\n%s\n' "────────────────────────────────────────────────────────────────"
printf 'passed %d · failed %d · blocked %d · skipped %d\n' "$PASS" "$FAIL" "$BLOCKED" "$SKIP"
[ "$FAIL" = 0 ] || printf 'failed:%s\n' "$FAILED_CASES"
[ "$BLOCKED" = 0 ] || printf 'blocked: the host could not answer. No verdict about these cases — run them again.\n'

# 0 = all green · 1 = a real failure · 2 = no failure, but blocked cases
if [ "$FAIL" != 0 ]; then exit 1
elif [ "$BLOCKED" != 0 ]; then exit 2
else exit 0
fi
