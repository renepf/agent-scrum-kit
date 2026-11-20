#!/usr/bin/env bash
CASE_DESC="the archive is history: a role may file and list, but not read — and the hook is registered"
CASE_KIND="static"
CASE_HOST="claude-code"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
out="$(python3 - "$KIT_ROOT" <<'PY'
import json, os, subprocess, sys
root = sys.argv[1]
guard = os.path.join(root, "adapters/claude-code/archive-guard.py")
errors, found = [], []

# 1. The hook has to be registered for the tools that read, or it protects nothing.
try:
    pre = json.load(open(os.path.join(root, "adapters/claude-code/settings.json")))["hooks"]["PreToolUse"]
except Exception as e:
    pre = []; errors.append("settings:%s" % e)
hooked = [e for e in pre for h in e.get("hooks", []) if "archive-guard.py" in h.get("command", "")]
if not hooked:
    errors.append("guard-not-registered")
for e in hooked:
    for t in ("Read", "Grep", "Glob", "Bash"):
        if t not in e.get("matcher", ""):
            errors.append("matcher-misses-%s" % t)
found.append("registered for %s" % (hooked[0].get("matcher") if hooked else "nothing"))

# 2. The guard itself. "deny" refuses, "" means the normal permission flow decides — answering
#    "allow" would wave every read of the session through, which is why it never does.
def ask(tool, ti, env=None):
    e = dict(os.environ); e.pop("ARCHIVE_GUARD_OFF", None); e.update(env or {})
    r = subprocess.run([sys.executable, guard], input=json.dumps(
        {"tool_name": tool, "tool_input": ti, "cwd": "/work/proj"}),
        capture_output=True, text=True, env=e)
    if r.returncode != 0:
        return "crash:" + r.stderr.strip().splitlines()[-1][:60]
    if not r.stdout.strip():
        return "pass"
    try:
        return json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"]
    except Exception as x:
        return "unreadable:%s" % x

CHECKS = [
    # reading the archive is refused, by every tool that reads
    ("deny", "Read",  {"file_path": "/work/proj/archive/old.md"}),
    ("deny", "Read",  {"file_path": "archive/old.md"}),                 # relative to cwd
    ("deny", "Read",  {"file_path": "/work/proj/docs/archive/old.md"}), # nested
    ("deny", "Grep",  {"pattern": "x", "path": "/work/proj/archive"}),
    ("deny", "Glob",  {"pattern": "archive/**/*.md"}),
    ("deny", "Bash",  {"command": "cat archive/old.md"}),
    ("deny", "Bash",  {"command": "cat archive/old.md | head -3"}),
    ("deny", "Bash",  {"command": "git show HEAD:archive/old.md"}),     # read through git
    # filing and listing stay open, or whoever archives cannot work
    ("pass", "Bash",  {"command": "mv comms/old.md archive/"}),
    ("pass", "Bash",  {"command": "git mv comms/old.md archive/"}),
    ("pass", "Bash",  {"command": "ls -la archive/"}),
    ("pass", "Bash",  {"command": "find archive -type f | wc -l"}),     # reader behind the pipe
    ("pass", "Write", {"file_path": "archive/new.md", "content": "x"}),
    # everything outside the archive is untouched
    ("pass", "Read",  {"file_path": "/work/proj/roles/po.md"}),
    ("pass", "Bash",  {"command": "cat roles/po.md"}),
    # a folder that merely ENDS in _archive is not an archive
    ("pass", "Read",  {"file_path": "/work/proj/build/dex_archive/f.jar"}),
]
for want, tool, ti in CHECKS:
    got = ask(tool, ti)
    if got != want:
        errors.append("%s(%s):want=%s,got=%s" % (tool, str(ti)[:34], want, got))
found.append("%d checks" % len(CHECKS))

# 3. The escape hatch exists and is the ONLY way through.
if ask("Read", {"file_path": "archive/old.md"}, {"ARCHIVE_GUARD_OFF": "1"}) != "pass":
    errors.append("escape-hatch-dead")
found.append("escape hatch works")

# 4. A template names no project. The guard is shipped, so it falls under case 43 as well —
#    this check says it out loud instead of leaving it to a grep over the whole tree.
text = open(guard, encoding="utf-8").read()
if "archive" not in text:
    errors.append("guard-does-not-mention-archive")
print("FOUND " + " · ".join(found))
print("ERRORS " + " ".join(errors))
PY
)"
found="$(printf '%s' "$out" | sed -n 's/^FOUND //p')"; errors="$(printf '%s' "$out" | sed -n 's/^ERRORS //p')"
observe "$found${errors:+ · ERRORS: $errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
