#!/usr/bin/env bash
# Maps a session id onto a fixture file.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$ROOT/evals/fixtures/$1.jsonl"
[ -f "$P" ] || exit 1
echo "$P"
