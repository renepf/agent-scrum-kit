#!/usr/bin/env bash
# Bildet eine Session-Kennung auf eine Fixture-Datei ab.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$ROOT/evals/fixtures/$1.jsonl"
[ -f "$P" ] || exit 1
echo "$P"
