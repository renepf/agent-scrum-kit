#!/usr/bin/env bash
# Before the first ticket access of every session. A failure is a failure,
# not a result — then you stop and report instead of guessing the state.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "$KIT_ISSUE_BACKEND" in
  gh)
    command -v gh > /dev/null || die "gh is not installed"
    LOGIN="$(gh api user -q .login 2>&1)" || {
      echo "$LOGIN" >&2
      case "$LOGIN" in
        *"missing required scopes"*) die "token valid, permission missing — add the scope, do NOT re-authenticate" ;;
        *"authentication"*|*"401"*)  die "token dead or absent — re-authenticate, do NOT request scopes" ;;
        *)                           die "GitHub preflight failed" ;;
      esac
    }
    echo "preflight ok · gh · $LOGIN · $KIT_REPO"
    ;;
  file)
    echo "preflight ok · file backend · ${KIT_ISSUE_FILE:-.kit-issues.json}"
    ;;
  *) die "KIT_ISSUE_BACKEND must be 'gh' or 'file'" ;;
esac
