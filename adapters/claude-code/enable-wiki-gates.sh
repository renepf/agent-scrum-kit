#!/usr/bin/env bash
# Owner-run patch: merge the three wiki hooks (S1 seed, S2 gate, S3 receipt) and their env into a
# Claude Code settings file. Prints the result and changes nothing unless --apply is given.
#   enable-wiki-gates.sh <settings.json> <WIKI_ROOT> <WIKI_GATE_PATHS> [<WIKI_REPOS>] [--apply]
# Effect on every session that reads that settings file: the seed lands in `messages` at start and
# an Edit/Write under WIKI_GATE_PATHS is denied until the session ran `wiki.sh query`.
# `wiki.sh` must be on PATH for those sessions (the denial names it), or the model cannot comply.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLY=""; ARGS=()
for a in "$@"; do [ "$a" = "--apply" ] && APPLY=1 || ARGS+=("$a"); done
[ "${#ARGS[@]}" -ge 3 ] || { sed -n 2,7p "$0" >&2; exit 64; }
python3 - "$KIT" "${ARGS[0]}" "${ARGS[1]}" "${ARGS[2]}" "${ARGS[3]:-}" "$APPLY" <<'PY'
import json, shutil, sys
kit, path, root, gate, repos, apply = sys.argv[1:7]
d = json.load(open(path))
hook = kit + "/adapters/claude-code/wiki-hook.sh"
def entry(mode, matcher=None):
    e = {"hooks": [{"type": "command", "command": f"{hook} {mode}", "timeout": 10}]}
    if matcher: e["matcher"] = matcher
    return e
h = d.setdefault("hooks", {})
for ev, e in (("SessionStart", entry("seed")), ("PreToolUse", entry("gate", "Edit|Write")), ("PostToolUse", entry("receipt", "Bash"))):
    lst = h.setdefault(ev, [])
    if not any(hook in x["command"] for g in lst for x in g.get("hooks", [])):
        lst.append(e)
env = d.setdefault("env", {})
env.update({"WIKI_ROOT": root, "WIKI_GATE_PATHS": gate})
if repos: env["WIKI_REPOS"] = repos
out = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
if apply:
    shutil.copy(path, path + ".bak-wiki"); open(path, "w").write(out); print(f"applied; backup {path}.bak-wiki")
else:
    print(out); print("dry run: nothing written (add --apply)", file=sys.stderr)
PY
