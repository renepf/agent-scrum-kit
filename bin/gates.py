#!/usr/bin/env python3
"""Gate ledger per ticket: <KIT_TICKETS_DIR>/<nr>/GATES.md.

A ledger is the checkable contract of a ticket: one gate per acceptance criterion, decided
either by a command (CHECK + EXPECT) or by a human with evidence (manual).

    # Gates: #754 make the partial loss of the catalogue visible

    OWNS: core/billing/**, core/billing/src/test/**

    - [ ] AC-1: missing prices appear as a hint in the paywall
      CHECK: <command that measures the result directly>
      EXPECT: <text only success prints>   or   /regex/flags
      CWD: <relative path, optional>
      EVIDENCE: pending

    - [ ] AC-2: hint visible on the running build
      EVIDENCE: pending

    ABANDON: AC-2 <reason and handover>

Format and rules are taken from unlazy (https://github.com/Leonxlnx/unlazy, at 1667149,
references/gates.md and scripts/gate-lint.mjs) and reimplemented here in Python. Deviations from the
original: gate ids of the form AC-<n> must appear in the issue; OWNS is mandatory, never frees the whole
root and knows ** only as a whole path segment; HTML comments, like code blocks, do not count.

unlazy is published under the following licence:

    MIT License

    Copyright (c) 2026 Leonxlnx

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

Usage (from bin/status.sh and bin/revise.sh):

    gates.py planned <ledger>    issue text on stdin. Exit 0 = the ledger covers every AC and starts fresh
                                 (no gate ticked, no ABANDON); then prints the OWNS of the ledger
    gates.py contract <ledger>   like planned, without the check for a fresh start (for revisions)
    gates.py approved            issue comments (JSON list) on stdin. Prints revision, tab, OWNS
                                 of the highest approval of the product-owner; exit 1 when there is none
    gates.py scope <owns>        file list of the PR on stdin. Exit 0 = every file lies within <owns>
    gates.py overlap [<label>]   lines "<label> TAB <owns>" on stdin (<owns> may also be "@<ledger>"). Exit 0 = no
                                 pair overlaps; with <label> only pairs this label takes part in
    gates.py run <ledger> <head8> <cwd> <role> <timeout>
                                 run every executable gate in <cwd>, evidence for <head8> into the ledger
    gates.py attest <ledger> <gate> <head8> <role> <evidence>
                                 attest a manual gate for <head8>
    gates.py unmet <ledger> <head8> runnable|all
                                 exit 0 = every (executable) gate has valid evidence for <head8>
    gates.py abandoned <ledger>  exit 0 = no gate given up (or no ledger); otherwise HANDOFF REQUIRED with the reason
    gates.py lint <ledger>       issue text on stdin. Lines "ERROR|HINT <gate> [<rule>]: ...";
                                 exit 1 as soon as one ERROR is among them. Runs no CHECK.
    gates.py qa-lines <ledger> <head8>
                                 PR comments (JSON list) on stdin. Exit 0 = every executable gate has, in
                                 a "QA PASS" for <head8>, a line "<gate>: mutation <what> → red"
    gates.py definitions <ledger>
                                 prints "<gate>=<definition digest>, ..." for the GATES Revision line of planned
    gates.py report <ledger> <head8>
                                 stdin: issue comments (JSON list), NUL, issue text. Prints each AC of the issue
                                 once next to its ledger state and whether its definition changed since approval.
                                 A measurement for the product-owner, never a gate: exit 0

Evidence holds for exactly one HEAD and one definition (CHECK, EXPECT, CWD). A push or a
changed line invalidates it. Green means: exit 0 and EXPECT in stdout plus stderr.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

GATE_RE = re.compile(r"^- \[([ xX])\]\s*(.*)$")
GATE_HEAD_RE = re.compile(r"^(\S+?):\s*(.*)$")
ATTR_RE = re.compile(r"^(\s+)(CHECK|EXPECT|EVIDENCE|CWD):\s?(.*)$")
UNINDENTED_ATTR_RE = re.compile(r"^(CHECK|EXPECT|EVIDENCE|CWD):")
ABANDON_RE = re.compile(r"^ABANDON:\s*(\S*)\s*(.*)$")
INDENTED_ABANDON_RE = re.compile(r"^\s+ABANDON:")
OWNS_RE = re.compile(r"^OWNS:\s*(.*)$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
AC_ID_RE = re.compile(r"^AC-\d+$")
ISSUE_AC_RE = re.compile(r"\bAC-\d+\b")
REGEX_EXPECT_RE = re.compile(r"^/(.+)/([a-z]*)$")
REGEX_FLAGS = {"i": re.I, "m": re.M, "s": re.S, "u": 0}
# An approval is a line in a comment whose first line was written by the product-owner
# (bin/status.sh planned, bin/revise.sh).
APPROVAL_HEAD_RE = re.compile(r"^\*\*[^*]+\*\* — product-owner · ")
APPROVAL_LINE_RE = re.compile(r"^OWNS Revision (\d+): `([^`]+)`\s*$")
GATES_LINE_RE = re.compile(r"^GATES Revision (\d+): `([^`]+)`\s*$")


def readable_lines(text):
    """Lines with their number, without fenced code blocks (CommonMark rules) and without HTML comments."""
    fence, comment = None, False
    for number, line in enumerate(text.splitlines(), 1):
        if fence is not None:
            m = FENCE_RE.match(line)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if comment:
            if "-->" not in line:
                continue
            line, comment = line.split("-->", 1)[1], False
        while "<!--" in line:
            before, rest = line.split("<!--", 1)
            if "-->" in rest:
                line = before + rest.split("-->", 1)[1]
            else:
                line, comment = before, True
        m = FENCE_RE.match(line)
        if m:
            fence = m.group(1)
            continue
        yield number, line


def relative_path_error(value, what):
    v = value.strip()
    if not v:
        return what + " is empty"
    if v.startswith("/") or re.match(r"^[A-Za-z]:", v):
        return what + " must be relative: " + v
    if ".." in v.replace("\\", "/").split("/"):
        return what + " must not contain '..': " + v
    if v in (".", "./"):
        return what + " must not be the whole root: " + v
    return None


def owns_error(value):
    err = relative_path_error(value, "OWNS path")
    if err:
        return err
    p = value.strip()
    p = p[2:] if p.startswith("./") else p
    if any("**" in s and s != "**" for s in p.split("/")):
        return "OWNS path: ** only as a whole path segment: " + value
    if not p.strip("*/?"):
        return "OWNS path frees the whole root: " + value
    return None


def compile_expect(expect):
    """EXPECT as (kind, value). /pattern/flags is a regular expression, otherwise a substring."""
    m = REGEX_EXPECT_RE.match(expect)
    if not m:
        return ("text", expect), None
    flags = 0
    for f in m.group(2):
        if f not in REGEX_FLAGS:
            return None, "EXPECT flag '%s' unknown (allowed: imsu)" % f
        flags |= REGEX_FLAGS[f]
    try:
        return ("regex", re.compile(m.group(1), flags)), None
    except re.error as e:
        return None, "EXPECT is not a valid regular expression: %s" % e


def parse(text):
    gates, owns, abandoned, errors = [], [], {}, []
    owns_seen, current = False, None
    for number, line in readable_lines(text):
        where = "line %d: " % number
        g = GATE_RE.match(line)
        if g:
            head = GATE_HEAD_RE.match(g.group(2).strip())
            if not head:
                errors.append(where + "gate without an id — format '- [ ] AC-1: <result>'")
                current = None
                continue
            current = {"id": head.group(1), "title": head.group(2).strip(), "checked": g.group(1) != " ",
                       "check": None, "expect": None, "cwd": None, "evidence": None, "line": number,
                       "evidence_line": None, "last_line": number}
            gates.append(current)
            continue
        if INDENTED_ABANDON_RE.match(line):
            errors.append(where + "ABANDON is indented and therefore does not count — write it at column 1")
            continue
        a = ATTR_RE.match(line)
        if a:
            if current is None:
                errors.append(where + a.group(2) + " stands under no gate")
                continue
            key = a.group(2).lower()
            if current[key] is not None:
                errors.append(where + "gate %s: %s twice" % (current["id"], a.group(2)))
                continue
            current[key] = a.group(3).strip()
            current["last_line"] = number
            if key == "evidence":
                current["evidence_line"] = number
            continue
        if UNINDENTED_ATTR_RE.match(line):
            errors.append(where + line.split(":")[0] + " is not indented and belongs to no gate")
            continue
        ab = ABANDON_RE.match(line)
        if ab:
            gid, reason = ab.group(1), ab.group(2).strip()
            if not gid or not reason:
                errors.append(where + "ABANDON needs a gate id and a reason")
            elif gid in abandoned:
                errors.append(where + "ABANDON for %s twice" % gid)
            else:
                abandoned[gid] = reason
            continue
        o = OWNS_RE.match(line)
        if o:
            if gates:
                errors.append(where + "OWNS must stand before the first gate")
            elif owns_seen:
                errors.append(where + "OWNS twice")
            else:
                owns_seen = True
                owns = [p.strip() for p in o.group(1).split(",") if p.strip()]
                errors.extend(where + e for e in map(owns_error, owns) if e)
            continue

    if not gates:
        errors.append("ledger without a gate")
    seen = set()
    for gate in gates:
        gid = gate["id"]
        if gid in seen:
            errors.append("gate id %s twice" % gid)
        seen.add(gid)
        if (gate["check"] is None) != (gate["expect"] is None):
            errors.append("gate %s: an executable gate needs CHECK and EXPECT, a manual one neither" % gid)
        elif gate["check"] is not None and (not gate["check"] or not gate["expect"]):
            errors.append("gate %s: CHECK and EXPECT must not be empty" % gid)
        elif gate["expect"]:
            gate["expectation"], err = compile_expect(gate["expect"])
            if err:
                errors.append("gate %s: %s" % (gid, err))
        if gate["cwd"] is not None:
            err = relative_path_error(gate["cwd"], "CWD")
            if err:
                errors.append("Gate %s: %s" % (gid, err))
    for gid in abandoned:
        if gid not in seen:
            errors.append("ABANDON names unknown gate %s" % gid)
    return {"gates": gates, "owns": owns, "abandoned": abandoned, "errors": errors}


def issue_acs(body):
    """Every AC-<n> in the issue text, in order and in every spelling: list, checkbox, table, quote."""
    acs = []
    for _, line in readable_lines(body):
        for ac in ISSUE_AC_RE.findall(line):
            if ac not in acs:
                acs.append(ac)
    return acs


class LedgerError(Exception):
    """A ledger that cannot be decoded. main() reports it as one line."""


def read(path):
    with open(path, "rb") as fh:
        data = fh.read()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise LedgerError("%s: not valid UTF-8 at byte %d" % (path, e.start))


def checked(text):
    """The parsed ledger; a formal error raises LedgerError, which main() prints in one line."""
    doc = parse(text)
    if doc["errors"]:
        raise LedgerError(" · ".join(doc["errors"]))
    return doc


def cmd_contract(ledger_path, fresh):
    try:
        doc = parse(read(ledger_path))
    except OSError:
        print("no ledger under %s — one gate per AC, the format is in bin/gates.py" % ledger_path)
        return 1
    acs = issue_acs(sys.stdin.read())
    errors = list(doc["errors"])
    if not acs:
        errors.append("the issue names no AC — one line per criterion, 'AC-<n>: <observable result>'")
    ids = [g["id"] for g in doc["gates"]]
    missing = [a for a in acs if a not in ids]
    if missing:
        errors.append("AC without a gate in the ledger: " + ", ".join(missing))
    unknown = [i for i in ids if AC_ID_RE.match(i) and acs and i not in acs]
    if unknown:
        errors.append("the ledger names ACs the issue does not know: " + ", ".join(unknown))
    if not doc["owns"]:
        errors.append("ledger without OWNS — which paths may this ticket change?")
    if fresh:
        checked = [g["id"] for g in doc["gates"] if g["checked"]]
        if checked:
            errors.append("gate already ticked before the work begins: " + ", ".join(checked))
        if doc["abandoned"]:
            errors.append("ABANDON before the work begins: " + ", ".join(doc["abandoned"]))
    if errors:
        print(" · ".join(errors))
        return 1
    print(", ".join(doc["owns"]))
    return 0


def split_owns(value):
    return [p.strip() for p in value.split(",") if p.strip()]


def glob_regex(pattern):
    """An OWNS glob as a regular expression: ** across directory boundaries, * and ? inside one name,
    a trailing / = everything below. Assumes a glob that owns_error allowed."""
    p = pattern.strip()
    p = p[2:] if p.startswith("./") else p
    rx = re.escape(p).replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*").replace(r"\?", "[^/]")
    return re.compile("^" + rx + (".*" if p.endswith("/") else "") + "$")


def approved_line(comments, line_re):
    """(revision, value) of the highest revision line in a product-owner comment; on a tie the latest wins."""
    best = None
    for body in comments:
        lines = body.splitlines()
        if not lines or not APPROVAL_HEAD_RE.match(lines[0]):
            continue
        for line in lines[1:]:
            m = line_re.match(line)
            if m and (best is None or int(m.group(1)) >= best[0]):
                best = (int(m.group(1)), m.group(2))
    return best


def cmd_approved():
    best = approved_line(json.loads(sys.stdin.read() or "[]"), APPROVAL_LINE_RE)
    if best is None:
        print("no approved OWNS revision on the issue — it comes from planned or bin/revise.sh")
        return 1
    print("%d\t%s" % best)
    return 0


def cmd_scope(owns):
    globs = split_owns(owns)
    files = [f.strip() for f in sys.stdin.read().splitlines() if f.strip()]
    if not files:
        print("the file list of the PR is empty — a failure, not a state")
        return 1
    patterns = [glob_regex(g) for g in globs]
    outside = [f for f in files if not any(p.match(f) for p in patterns)]
    if outside:
        print("files outside OWNS (%s): %s · only the product-owner approves an extension: bin/revise.sh"
              % (", ".join(globs), ", ".join(outside)))
        return 1
    print("scope ok: %d files" % len(files))
    return 0


def globs_overlap(a, b):
    """Can two OWNS globs mean the same file? In doubt, yes.
    A path without a glob is exactly one file: then it decides whether the other glob matches it. Otherwise the
    segment rule from unlazy (globsOverlap): separate only when a literal segment differs before
    a glob character stands on either side."""
    def is_file(p):
        return not re.search(r"[*?]", p) and not p.endswith("/")
    a, b = (p.strip()[2:] if p.strip().startswith("./") else p.strip() for p in (a, b))
    if is_file(a):
        return bool(glob_regex(b).match(a))
    if is_file(b):
        return bool(glob_regex(a).match(b))
    for x, y in zip([s for s in a.split("/") if s], [s for s in b.split("/") if s]):
        if re.search(r"[*?]", x) or re.search(r"[*?]", y):
            return True
        if x != y:
            return False
    return True


def cmd_overlap(only):
    claims = []
    for line in sys.stdin.read().splitlines():
        if "\t" not in line:
            continue
        label, owns = line.split("\t", 1)
        if owns.startswith("@"):
            owns = ", ".join(parse(read(owns[1:]))["owns"])
        claims.append((label, split_owns(owns)))
    conflicts = []
    for i, (la, ga) in enumerate(claims):
        for lb, gb in claims[i + 1:]:
            if only and only not in (la, lb):
                continue
            pairs = ["%s ~ %s" % (x, y) for x in ga for y in gb if globs_overlap(x, y)]
            if pairs:
                conflicts.append("%s and %s overlap: %s" % (la, lb, ", ".join(pairs)))
    if conflicts:
        print(" · ".join(conflicts) + " · two engineers work in parallel, OWNS must be separate")
        return 1
    return 0


def definition_digest(gate):
    raw = json.dumps([gate["check"] or "", gate["expect"] or "", gate["cwd"] or ""])
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def gate_problem(gate, head8):
    """None when the gate has valid evidence for head8, otherwise the reason."""
    evidence = gate["evidence"] or "pending"
    if gate["check"] is None:
        return None if evidence.startswith("manual head=%s " % head8) else "manual without evidence for this HEAD"
    if not evidence.startswith("v1 "):
        return "never ran green"
    fields = dict(f.split("=", 1) for f in evidence.split() if "=" in f)
    if fields.get("head") != head8:
        return "evidence holds for HEAD %s" % fields.get("head", "?")
    if fields.get("def") != definition_digest(gate):
        return "definition changed since the run"
    if fields.get("exit") != "0" or fields.get("expect") != "matched":
        return "no green run"
    return None


def write_results(path, text, doc, results):
    """results: {gate id: (ticked, evidence)}. Changes only the checkbox and the EVIDENCE line, writes atomically."""
    lines = text.splitlines(keepends=True)
    nl = "\r\n" if "\r\n" in text else "\n"
    edits = []
    for gate in doc["gates"]:
        if gate["id"] in results:
            checked, evidence = results[gate["id"]]
            edits.append((gate["line"], "box", checked))
            if gate["evidence_line"]:
                edits.append((gate["evidence_line"], "evidence", evidence))
            else:
                edits.append((gate["last_line"], "insert", evidence))
    for number, kind, value in sorted(edits, key=lambda e: e[0], reverse=True):
        i = number - 1
        if kind == "box":
            lines[i] = re.sub(r"^- \[[ xX]\]", "- [x]" if value else "- [ ]", lines[i])
        elif kind == "evidence":
            lines[i] = "%sEVIDENCE: %s%s" % (re.match(r"^(\s*)", lines[i]).group(1), value, nl)
        else:
            lines.insert(number, "  EVIDENCE: %s%s" % (value, nl))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write("".join(lines))
    os.replace(tmp, path)


def cmd_run(path, head8, cwd, role, timeout):
    text = read(path)
    doc = checked(text)
    results, report = {}, []
    for gate in doc["gates"]:
        if gate["check"] is None or gate["id"] in doc["abandoned"]:
            continue
        combined = ""
        try:
            p = subprocess.run(gate["check"], shell=True, cwd=os.path.join(cwd, gate["cwd"] or ""),
                               capture_output=True, timeout=float(timeout))
            out, err = p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
            combined = out + ("\n" if out and err else "") + err
            kind, value = gate["expectation"]
            matched = value in combined if kind == "text" else bool(value.search(combined))
            why = None if p.returncode == 0 and matched else \
                "exit=%d, EXPECT %s" % (p.returncode, "found" if matched else "not found")
        except subprocess.TimeoutExpired:
            why = "timed out after %s s" % timeout
        except OSError as e:
            why = "not startable: %s" % e
        if why is None:
            results[gate["id"]] = (True, "v1 head=%s def=%s exit=0 expect=matched out=%s at=%s by=%s" % (
                head8, definition_digest(gate), hashlib.sha256(combined.encode("utf-8")).hexdigest()[:12], time.strftime("%Y-%m-%dT%H:%M"), role))
            report.append("%s green" % gate["id"])
        else:
            results[gate["id"]] = (False, "pending")
            report.append("%s RED: %s · %s" % (gate["id"], why, " ".join(combined.split())[-200:]))
    if not results:
        print("no executable gates in the ledger")
        return 0
    write_results(path, text, doc, results)
    print("\n".join(report))
    return 0 if all(ok for ok, _ in results.values()) else 1


def cmd_attest(path, gid, head8, role, evidence):
    text = read(path)
    doc = checked(text)
    gate = next((g for g in doc["gates"] if g["id"] == gid), None)
    evidence = " ".join(evidence.split())
    problem = ("gate %s does not exist in the ledger" % gid if gate is None else
               "gate %s is executable — its evidence comes only from bin/gates.sh run" % gid if gate["check"] is not None else
               "gate %s is given up via ABANDON" % gid if gid in doc["abandoned"] else
               "evidence needs text" if not evidence else None)
    if problem:
        print(problem)
        return 1
    write_results(path, text, doc, {gid: (True, "manual head=%s by=%s at=%s — %s" % (head8, role, time.strftime("%Y-%m-%dT%H:%M"), evidence))})
    print("%s attested for HEAD %s" % (gid, head8))
    return 0


def cmd_unmet(path, head8, mode):
    doc = checked(read(path))
    problems = []
    for gate in doc["gates"]:
        if gate["id"] in doc["abandoned"] or (mode == "runnable" and gate["check"] is None):
            continue
        why = gate_problem(gate, head8)
        if why:
            problems.append("%s (%s)" % (gate["id"], why))
    if problems:
        print("gates not green for HEAD %s: %s · executable ones with bin/gates.sh run, manual ones with bin/gates.sh attest"
              % (head8, ", ".join(problems)))
        return 1
    print("all gates green for HEAD %s" % head8)
    return 0


# Gate lint after unlazy scripts/gate-lint.mjs: lexical signs of oracles that cannot fall.
# The first four rules reject, the rest is a hint. German words are kept in the word lists on
# purpose: they are detector data for German-language projects, not user-facing text.
FIXED_OUTPUT_COMMAND = re.compile(r"^\s*(?:(?:echo|printf)(?:\s+[^&|;]*)?|true|:|exit\s+0)\s*$", re.I)
WEAK_EXPECT = {
    "ok", "okay", "done", "pass", "passed", "success", "successful", "succeeded", "complete", "completed",
    "finished", "yes", "true", "0", "good", "fine", "working",
    "fertig", "erledigt", "bestanden", "erfolgreich", "erfolg", "gruen", "grün", "ja", "gut", "passt", "laeuft", "läuft",
}
ACTIVITY_TITLE = re.compile(
    r"^(work(ing)? on|improve|enhance|handle|support|ensure|make sure|try|attempt|look (at|into)|investigate|consider"
    r"|review|refactor|clean ?up|polish|update|tidy|address|deal with|add support)\b"
    r"|\b(verbessern|optimieren|ueberarbeiten|überarbeiten|aufraeumen|aufräumen|sicherstellen|unterstuetzen|unterstützen"
    r"|behandeln|anpassen|untersuchen|pruefen|prüfen|refaktorieren)\b", re.I)
NUMBER_RE = re.compile(r"\d+(?:[.,]\d+)?")


def lint_findings(doc, body):
    issue_numbers = set(NUMBER_RE.findall(body))
    live = [g for g in doc["gates"] if g["id"] not in doc["abandoned"]]
    found = []
    for g in live:
        gid, title, check, expect = g["id"], g["title"], g["check"], g["expect"]
        if check is not None:
            kind, value = g["expectation"]
            if FIXED_OUTPUT_COMMAND.match(check):
                found.append(("ERROR", gid, "tautological-check",
                              "CHECK prints fixed text ('%s') — an oracle measures the result itself" % check))
            if expect.strip().lower() in WEAK_EXPECT:
                found.append(("ERROR", gid, "weak-expect",
                              "EXPECT '%s' appears in error output too — demand a line only success prints" % expect))
            if kind == "regex" and re.search(r"(^|[^\\])/", value.pattern):
                found.append(("ERROR", gid, "path-read-as-regex",
                              "EXPECT '%s' is a regular expression, dots are placeholders — escape the inner / "
                              "or drop the surrounding /" % expect))
            if kind == "text" and re.fullmatch(r"[\d\s.,:%/-]+", expect.strip()) and \
                    all(x in issue_numbers for x in NUMBER_RE.findall(expect)):
                found.append(("ERROR", gid, "copied-number",
                              "EXPECT '%s' is only a number from the issue — the script measures it at the source and "
                              "prints a success line of its own" % expect))
        else:
            found.append(("HINT", gid, "manual-gate",
                          "no CHECK: a human judges the result, the evidence is only as good as the reader"))
            if re.search(r"\d", title):
                found.append(("HINT", gid, "unmeasured-number", "the title names a number that measures nothing: '%s'" % title))
        if ACTIVITY_TITLE.search(title):
            found.append(("HINT", gid, "activity-not-outcome",
                          "the title names an activity, not a result a stranger can judge: '%s'" % title))
    runnable = sum(1 for g in live if g["check"] is not None)
    if live and runnable / len(live) < 0.5:
        found.append(("HINT", "ledger", "mostly-manual",
                      "%d of %d gates are executable — a mostly manual ledger is prose with boxes" % (runnable, len(live))))
    return found


def cmd_lint(path):
    doc = parse(read(path))
    body = sys.stdin.read()
    found = [("ERROR", "ledger", "parse", e) for e in doc["errors"]] or lint_findings(doc, body)
    for level, gid, rule, message in found:
        print("%s %s [%s]: %s" % (level, gid, rule, message))
    return 1 if any(level == "ERROR" for level, _, _, _ in found) else 0


def cmd_qa_lines(path, head8):
    doc = parse(read(path))
    lines = []
    for body in json.loads(sys.stdin.read() or "[]"):
        rows = body.splitlines()
        if rows and rows[0].startswith("QA PASS") and head8 in rows[0]:
            lines.extend(rows[1:])
    missing = [g["id"] for g in doc["gates"] if g["check"] is not None and g["id"] not in doc["abandoned"]
               and not any(re.match(r"^\s*%s: mutation \S.*(→|->) red\s*$" % re.escape(g["id"]), row) for row in lines)]
    if missing:
        print("the QA PASS for HEAD %s names no mutation for: %s — one line per executable gate, "
              "'<gate>: mutation <what> → red'" % (head8, ", ".join(missing)))
        return 1
    return 0


def cmd_abandoned(path):
    """A gate given up is a visible handover, never a finished one. Without a ledger: nothing given up —
    that a ledger is missing is checked by unmet."""
    try:
        doc = checked(read(path))
    except OSError:
        return 0
    if doc["abandoned"]:
        print("HANDOFF REQUIRED: %s · the product-owner decides: take the AC out of issue and ledger with a follow-up ticket, "
              "or send the ticket back" % ", ".join("%s (%s)" % kv for kv in doc["abandoned"].items()))
        return 1
    return 0


def cmd_definitions(path):
    """Runs after planned accepted the ledger, so it prints without a second parse check."""
    doc = parse(read(path))
    print(", ".join("%s=%s" % (g["id"], definition_digest(g)) for g in doc["gates"]))
    return 0


def cmd_report(path, head8):
    comments, _, body = sys.stdin.read().partition("\0")
    acs = issue_acs(body)
    out = []
    try:
        doc = parse(read(path))
        if doc["errors"]:
            out.append("ledger: " + " · ".join(doc["errors"]))
    except (OSError, LedgerError) as e:
        doc = {"gates": [], "abandoned": {}}
        out.append("ledger: not readable: %s" % e)
    best = approved_line(json.loads(comments or "[]"), GATES_LINE_RE)
    approved = dict(p.strip().split("=", 1) for p in best[1].split(",") if "=" in p) if best else None
    if approved is None:
        out.append("approved definitions: none on the issue — no 'GATES Revision' line from the product-owner")
    if not acs:
        out.append("acceptance criteria: none in the issue")
    gates = {g["id"]: g for g in doc["gates"]}
    for gid in acs + [g for g in gates if g not in acs]:
        gate, parts = gates.get(gid), []
        if gid not in acs:
            parts.append("not in the issue")
        if gate is None:
            parts.append("no gate in the ledger")
        elif gid in doc["abandoned"]:
            parts.append("ABANDONED: " + doc["abandoned"][gid])
        else:
            problem = gate_problem(gate, head8)
            parts.append("not green (%s)" % problem if problem else
                         "%s for HEAD %s" % ("attested" if gate["check"] is None else "green", head8))
        if gate is not None and approved is not None:
            if gid not in approved:
                parts.append("not in the approved definitions")
            elif approved[gid] != definition_digest(gate):
                parts.append("definition changed since approval")
        out.append("%s: %s%s" % (gid, "; ".join(parts), " · " + gate["title"] if gate else ""))
    print("\n".join("  " + line for line in out))
    return 0


COMMANDS = {
    ("abandoned", 1): lambda a: cmd_abandoned(a[0]),
    ("definitions", 1): lambda a: cmd_definitions(a[0]),
    ("report", 2): lambda a: cmd_report(*a),
    ("lint", 1): lambda a: cmd_lint(a[0]),
    ("qa-lines", 2): lambda a: cmd_qa_lines(*a),
    ("run", 5): lambda a: cmd_run(*a),
    ("attest", 5): lambda a: cmd_attest(*a),
    ("unmet", 3): lambda a: cmd_unmet(*a),
    ("planned", 1): lambda a: cmd_contract(a[0], fresh=True),
    ("contract", 1): lambda a: cmd_contract(a[0], fresh=False),
    ("approved", 0): lambda a: cmd_approved(),
    ("scope", 1): lambda a: cmd_scope(a[0]),
    ("overlap", 0): lambda a: cmd_overlap(None),
    ("overlap", 1): lambda a: cmd_overlap(a[0]),
}


def main(argv):
    run = COMMANDS.get((argv[0], len(argv) - 1)) if argv else None
    if run is None:
        sys.stderr.write(__doc__.split("Usage")[-1])
        return 2
    try:
        return run(argv[1:])
    except (OSError, LedgerError, UnicodeDecodeError) as e:
        # Fail closed in one line: every caller stops on the exit code before it writes anything.
        print("gates.py %s: %s" % (argv[0], e))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
