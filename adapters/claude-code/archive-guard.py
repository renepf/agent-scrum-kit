#!/usr/bin/env python3
"""PreToolUse guard: no role reads out of the archive.

Archived files are history. A role that reads them pulls retired plans, superseded findings and
stale status back into a live session and treats them as current state. The rule holds for every
directory called `archive` below the project: a role may put files there and list what is in there,
but not read their content.

What this blocks
    Read, Grep, Glob on a path inside an archive directory, and a Bash command that pairs an
    archive path with a reading utility (cat, head, grep, sed, git show, ...).

What this deliberately does NOT block
    Writing and moving. The agent that fills the archive has to put files there, so mv, cp, rsync,
    git mv and git add stay open. Listing stays open too: ls and find answer "what is in there",
    which is not reading the content.

What this cannot promise
    It checks the words of a command. A read hidden behind a script, a shell variable or a symlink
    into the archive passes. The honest criterion is: an archive path next to a reading word in the
    same pipeline segment is refused. Case 100 holds this contract.

Escape hatch
    ARCHIVE_GUARD_OFF=1 in the environment turns it off for that one call. Whoever archives needs
    it when they have to compare what they moved.
"""
import json
import os
import re
import sys

# A path component that is EXACTLY "archive". Exactly matters: a build folder whose name merely ends
# in "_archive" is not an archive, and the component test leaves it alone.
ARCHIVE_RE = re.compile(r"(^|/)archive(/|$)")

# Reads the content of a file.
READERS = {
    "cat", "head", "tail", "less", "more", "bat", "nl", "od", "xxd", "strings",
    "sed", "awk", "grep", "egrep", "fgrep", "rg", "ag", "ack", "wc", "sort", "uniq",
    "diff", "cmp", "md5", "shasum", "open", "cut", "tr", "jq", "yq", "python", "python3",
    "ruby", "perl", "node", "pandoc", "textutil",
}
# Reading through git, which never touches the working tree.
GIT_READERS = {"show", "cat-file", "grep", "log", "blame", "diff"}

# One pipeline segment. A reading word behind a pipe reads the previous output, not the archive.
SEGMENT_RE = re.compile(r"\|\||&&|[|;\n]")

# Something that looks like a path in a shell command.
TOKEN_RE = re.compile(r"[^\s'\";|&<>()]+")


def out(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


def passthrough():
    """No hit: say nothing and let the normal permission flow decide. Never answer 'allow' here —
    that would wave through every Read and every Bash call in the session."""
    sys.exit(0)


def in_archive(path, cwd):
    if not path:
        return False
    # git reads a path behind a revision: "HEAD:archive/plan.md", "origin/main:archive/x".
    if ":" in path and not path.startswith("/"):
        path = path.split(":", 1)[1]
    p = path if os.path.isabs(path) else os.path.join(cwd or "", path)
    # normpath only, never realpath: resolving symlinks would need the file to exist, and a
    # pattern like "archive/**/*.md" has no file behind it.
    return bool(ARCHIVE_RE.search(os.path.normpath(p)))


if os.environ.get("ARCHIVE_GUARD_OFF") == "1":
    passthrough()

try:
    data = json.load(sys.stdin)
except Exception:
    passthrough()      # an unreadable hook input is not a reason to block the session

tool = data.get("tool_name", "")
ti = data.get("tool_input") or {}
cwd = data.get("cwd") or os.getcwd()
if not isinstance(ti, dict):
    passthrough()

REFUSED = ("archive guard: %s points into the archive. Archived files are history — reading them "
           "pulls retired plans and stale status into a live session. If you need it anyway, the "
           "owner decides: ARCHIVE_GUARD_OFF=1 for that one call, and say in the chat why.")

if tool == "Read":
    p = ti.get("file_path", "")
    if in_archive(p, cwd):
        out("deny", REFUSED % p)
    passthrough()

if tool in ("Grep", "Glob"):
    for key in ("path", "pattern", "glob"):
        v = ti.get(key, "")
        if isinstance(v, str) and in_archive(v, cwd):
            out("deny", REFUSED % v)
    passthrough()

if tool == "Bash":
    cmd = ti.get("command", "")
    if not isinstance(cmd, str):
        passthrough()
    if not any(in_archive(t.strip("'\""), cwd) for t in TOKEN_RE.findall(cmd)):
        passthrough()
    # Per pipeline segment, not per command: in "find archive -type f | wc -l" the reading word sits
    # behind the pipe and reads a listing, not an archived file. Only a segment that carries BOTH
    # the path and the reading word is a read of the archive.
    for seg in SEGMENT_RE.split(cmd):
        tokens = TOKEN_RE.findall(seg)
        hit = next((t for t in tokens if in_archive(t.strip("'\""), cwd)), None)
        if not hit:
            continue
        words = [os.path.basename(t).lower() for t in tokens]
        reading = [w for w in words if w in READERS]
        if "git" in words:
            # git show HEAD:archive/... reads without the file ever being in the working tree.
            reading += [w for w in words if w in GIT_READERS]
        if reading:
            out("deny", (REFUSED % hit) + " (reading word: '%s')" % reading[0])
    passthrough()

passthrough()
