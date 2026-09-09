#!/usr/bin/env bash
# Den Sprint-Stand committen. NUR der watchdog, im Takt.
# Neun parallele 'git pull --rebase' sind die einzige echte Konfliktquelle im Kit.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPRINT="$(sprint_dir)"
kit_commit_all "chore(sprint): $(basename "$SPRINT") Stand $(now)"
echo "Sprint-Stand committet"
