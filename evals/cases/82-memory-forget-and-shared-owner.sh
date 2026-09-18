#!/usr/bin/env bash
CASE_DESC="wrong facts are deleted, not amended; a shared fact is changed and deleted only by its author"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
errors=""
KIT_ROLE=security-engineer "$BIN/brain.sh" share token-in-the-log "tokens land in the debug log" <<<'Measured 2026-09-10.' > /dev/null || errors="$errors share"
o1="$(KIT_ROLE=engineer-b "$BIN/brain.sh" share token-in-the-log "tokens no longer land in the log" <<<'x' 2>&1)"
case "$o1" in *"belongs to security-engineer"*) ;; *) errors="$errors foreign-overwrite-let-through" ;; esac
o2="$(KIT_ROLE=engineer-b "$BIN/brain.sh" forget token-in-the-log --shared 2>&1)"
case "$o2" in *"only the author"*) ;; *) errors="$errors foreign-delete-let-through" ;; esac
KIT_ROLE=security-engineer "$BIN/brain.sh" forget token-in-the-log --shared > /dev/null 2>&1 || errors="$errors author-may-not-delete"
[ ! -f "$SANDBOX/memory/_shared/facts/token-in-the-log.md" ] || errors="$errors file-still-there"
grep -q 'token-in-the-log' "$SANDBOX/memory/_shared/INDEX.md" && errors="$errors index-shows-the-deleted-fact"
o3="$(KIT_ROLE=security-engineer "$BIN/brain.sh" forget token-in-the-log --shared 2>&1)"
case "$o3" in *"does not exist"*) ;; *) errors="$errors second-delete-reports-success" ;; esac
observe "a foreign overwrite → refused · a foreign delete → refused · the author deletes → the file and the index line are gone · deleting again → 'does not exist'${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
