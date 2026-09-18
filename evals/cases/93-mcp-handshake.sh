#!/usr/bin/env bash
CASE_DESC="every shipped MCP server answers initialize and tools/list, through caveman-shrink (real package downloads)"
CASE_KIND="net"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
cd "$KIT_ROOT"
found=""; errors=""
for f in .mcp.json adapters/claude-code/mcp/jcodemunch.json; do
  while IFS=$'\t' read -r name cmd; do
    r="$(eval "python3 '$KIT_ROOT/evals/lib/mcp-probe.py' $cmd" 2>&1 | head -1)"
    case "$r" in
      serverInfo=*) found="$found $name: $(echo "$r" | grep -oE '[0-9]+ tools') ·" ;;
      *) errors="$errors $name:'$(echo "$r" | cut -c1-80)'" ;;
    esac
  done < <(python3 -c 'import json,shlex,sys
for n,s in json.load(open(sys.argv[1]))["mcpServers"].items():
    print(n + "\t" + " ".join(shlex.quote(x) for x in [s["command"]] + s["args"]))' "$f")
done
case "$errors" in *"No module"*|*"ENOTFOUND"*|*"Could not"*) echo "OBSERVED: BLOCKED —$errors"; exit 3 ;; esac
observe "${found% ·}${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
