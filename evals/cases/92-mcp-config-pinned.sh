#!/usr/bin/env bash
CASE_DESC="MCP configuration: valid JSON, every version pinned exactly, every stdio server through caveman-shrink, jcodemunch on opt-in only"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
out="$(python3 - "$KIT_ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
errors, found = [], []
def load(p):
    try:
        return json.load(open(os.path.join(root, p)))["mcpServers"]
    except Exception as e:
        errors.append(f"{p}:invalid({e})"); return {}
std = load(".mcp.json"); opt = load("adapters/claude-code/mcp/jcodemunch.json")
if "jcodemunch" in std: errors.append("jcodemunch-on-by-default")
if set(std) != {"context7", "graphify"}: errors.append(f"default-servers={sorted(std)}")
if set(opt) != {"jcodemunch"}: errors.append(f"opt-in-servers={sorted(opt)}")
# package@version, package==version or package[extra]==version — anything else is unpinned.
PIN = re.compile(r"^(@?[a-z0-9][\w./-]*@\d+\.\d+\.\d+|[a-z0-9][\w.-]*(\[[\w,]+\])?==\d+\.\d+\.\d+)$")
for name, s in {**std, **opt}.items():
    args = s.get("args", [])
    if s.get("command") != "npx" or args[:2] != ["-y", "caveman-shrink@0.1.0"]:
        errors.append(f"{name}:not-through-caveman-shrink@0.1.0")
    pkgs = [a for a in args if "@" in a[1:] or "==" in a]
    if not pkgs: errors.append(f"{name}:no-package-found")
    for a in pkgs:
        if not PIN.match(a): errors.append(f"{name}:unpinned:{a}")
    found.append(f"{name}=" + ",".join(p for p in pkgs if "caveman" not in p))
# --mcp-config ADDS to the globally configured servers; only --strict-mcp-config pins the
# session to exactly this list. Measured 2026-09-29 with the same one-shot call: 51 346 tokens
# plain, 52 172 with --mcp-config alone, 35 428 with --strict-mcp-config.
loop = open(os.path.join(root, "adapters/claude-code/role-loop.sh")).read()
starts = [l for l in loop.splitlines() if "--mcp-config" in l and not l.lstrip().startswith("#")]
if not starts:
    errors.append("role-loop:starts-without-mcp-config")
for l in starts:
    if "--strict-mcp-config" not in l:
        errors.append("role-loop:mcp-config-without-strict")
found.append("role start pins %d config(s) strictly" % len(starts))
lic = open(os.path.join(root, "adapters/claude-code/README.md")).read()
if "Dual-Use" not in lic or "revenue" not in lic: errors.append("licence-note-jcodemunch-missing")
print("FOUND " + " · ".join(found))
print("ERRORS " + " ".join(errors))
PY
)"
found="$(printf '%s' "$out" | sed -n 's/^FOUND //p')"; errors="$(printf '%s' "$out" | sed -n 's/^ERRORS //p')"
observe "$found · jcodemunch opt-in only${errors:+ · ERRORS: $errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
