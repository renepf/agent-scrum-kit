#!/usr/bin/env bash
CASE_DESC="the tick shows every foreign entry exactly once, even within the same minute"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
SPRINT="$(sandbox_sprint)"
export KIT_ROLE=engineer-a

# Fixed timestamps so the trap really springs: two entries of the same minute.
# On a tie the index sorts by file name — acceptance-tester before qa-ruthless.
# A counter of "lines since the last tick" would then show the OLD entry.
printf '# chat\n\n## 2026-01-01 10:00 · qa-ruthless · #1 · first\nrumpf\n' > "$SPRINT/chat/qa-ruthless.md"
"$BIN/reindex.sh" > /dev/null
t1="$("$BIN/tick.sh" 2>&1)"
t2="$("$BIN/tick.sh" 2>&1)"
printf '# chat\n\n## 2026-01-01 10:00 · acceptance-tester · #1 · second\nrumpf\n' > "$SPRINT/chat/acceptance-tester.md"
"$BIN/reindex.sh" > /dev/null
t3="$("$BIN/tick.sh" 2>&1)"

errors=""
case "$t1" in *"first"*) ;; *) errors="$errors tick1-does-not-show-the-first" ;; esac
case "$t2" in *"no new"*) ;; *) errors="$errors tick2-shows-it-again" ;; esac
case "$t3" in *"second"*) ;; *) errors="$errors tick3-does-not-show-the-new-one" ;; esac
case "$t3" in *"first"*) errors="$errors tick3-shows-the-old-one-again" ;; esac

observe "tick1 shows 'first' · tick2 nothing · tick3 only 'second' (same minute, sorted before it)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
