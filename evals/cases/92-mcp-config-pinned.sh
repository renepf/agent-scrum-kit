#!/usr/bin/env bash
CASE_DESC="MCP-Konfiguration: gueltiges JSON, jede Version exakt gepinnt, jeder stdio-Server durch caveman-shrink, jcodemunch nur auf Einschalten"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
out="$(python3 - "$KIT_ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
fehler, befund = [], []
def load(p):
    try:
        return json.load(open(os.path.join(root, p)))["mcpServers"]
    except Exception as e:
        fehler.append(f"{p}:ungueltig({e})"); return {}
std = load(".mcp.json"); opt = load("adapters/claude-code/mcp/jcodemunch.json")
if "jcodemunch" in std: fehler.append("jcodemunch-standardmaessig-an")
if set(std) != {"context7", "graphify"}: fehler.append(f"standard-server={sorted(std)}")
if set(opt) != {"jcodemunch"}: fehler.append(f"opt-in-server={sorted(opt)}")
# Paket@Version, paket==version oder paket[extra]==version — alles andere ist ungepinnt.
PIN = re.compile(r"^(@?[a-z0-9][\w./-]*@\d+\.\d+\.\d+|[a-z0-9][\w.-]*(\[[\w,]+\])?==\d+\.\d+\.\d+)$")
for name, s in {**std, **opt}.items():
    args = s.get("args", [])
    if s.get("command") != "npx" or args[:2] != ["-y", "caveman-shrink@0.1.0"]:
        fehler.append(f"{name}:nicht-durch-caveman-shrink@0.1.0")
    pkgs = [a for a in args if "@" in a[1:] or "==" in a]
    if not pkgs: fehler.append(f"{name}:kein-paket-gefunden")
    for a in pkgs:
        if not PIN.match(a): fehler.append(f"{name}:ungepinnt:{a}")
    befund.append(f"{name}=" + ",".join(p for p in pkgs if "caveman" not in p))
lic = open(os.path.join(root, "adapters/claude-code/README.md")).read()
if "Dual-Use" not in lic or "revenue" not in lic: fehler.append("lizenzhinweis-jcodemunch-fehlt")
print("BEFUND " + " · ".join(befund))
print("FEHLER " + " ".join(fehler))
PY
)"
befund="$(printf '%s' "$out" | sed -n 's/^BEFUND //p')"; fehler="$(printf '%s' "$out" | sed -n 's/^FEHLER //p')"
observe "$befund · jcodemunch nur opt-in${fehler:+ · FEHLER: $fehler}"
echo "BEOBACHTET: $OBSERVED"
[ -z "$fehler" ]
