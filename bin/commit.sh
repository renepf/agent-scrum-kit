#!/usr/bin/env bash
# Commit the sprint state. ONLY the watchdog, on its interval.
# Nine parallel 'git pull --rebase' are the only real source of conflict in the kit.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPRINT="$(sprint_dir)"
kit_commit_all "chore(sprint): $(basename "$SPRINT") state $(now)"
echo "sprint state committed"
