#!/usr/bin/env bash
# Vor dem ersten Ticketzugriff jeder Session. Ein Fehlschlag ist ein Fehlschlag,
# kein Ergebnis — dann stoppst du und meldest, statt den Zustand zu raten.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "$KIT_ISSUE_BACKEND" in
  gh)
    command -v gh > /dev/null || die "gh ist nicht installiert"
    LOGIN="$(gh api user -q .login 2>&1)" || {
      echo "$LOGIN" >&2
      case "$LOGIN" in
        *"missing required scopes"*) die "Token gueltig, Berechtigung fehlt — Scope nachziehen, NICHT neu anmelden" ;;
        *"authentication"*|*"401"*)  die "Token tot oder fehlt — neu anmelden, KEINE Scopes anfordern" ;;
        *)                           die "GitHub-Preflight fehlgeschlagen" ;;
      esac
    }
    echo "preflight ok · gh · $LOGIN · $KIT_REPO"
    ;;
  file)
    echo "preflight ok · file-backend · ${KIT_ISSUE_FILE:-.kit-issues.json}"
    ;;
  *) die "KIT_ISSUE_BACKEND muss 'gh' oder 'file' sein" ;;
esac
