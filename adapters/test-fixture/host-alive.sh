#!/usr/bin/env bash
# Evals: KIT_HOST_ALIVE_NAME legt fest, welcher Prozessname als Host gilt (Standard: jeder lebende Prozess).
set -euo pipefail
comm="$(ps -o comm= -p "$1" 2>/dev/null)" || exit 1
[ -z "${KIT_HOST_ALIVE_NAME:-}" ] || [ "$(basename "$comm")" = "$KIT_HOST_ALIVE_NAME" ]
