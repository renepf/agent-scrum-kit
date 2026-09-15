#!/usr/bin/env python3
"""Gate-Ledger je Ticket: <KIT_TICKETS_DIR>/<nr>/GATES.md.

Ein Ledger ist der pruefbare Vertrag eines Tickets: je Acceptance-Kriterium ein Gate, das
entweder ein Befehl entscheidet (CHECK + EXPECT) oder ein Mensch mit Beleg (manuell).

    # Gates: #754 Teil-Wegfall des Katalogs sichtbar machen

    OWNS: core/billing/**, core/billing/src/test/**

    - [ ] AC-1: fehlende Preise erscheinen als Hinweis in der Paywall
      CHECK: <befehl, der das Ergebnis direkt misst>
      EXPECT: <text, den nur der Erfolg druckt>   oder   /regex/flags
      CWD: <relativer pfad, optional>
      EVIDENCE: pending

    - [ ] AC-2: Hinweis am laufenden Bau sichtbar
      EVIDENCE: pending

    ABANDON: AC-2 <grund und uebergabe>

Format und Regeln sind uebernommen aus unlazy (https://github.com/Leonxlnx/unlazy, Stand 1667149,
references/gates.md und scripts/gate-lint.mjs) und hier in Python neu umgesetzt. Abweichungen vom
Original: Gate-IDs der Form AC-<n> muessen im Issue vorkommen; OWNS ist Pflicht, gibt nie die ganze
Wurzel frei und kennt ** nur als ganzes Pfadsegment; HTML-Kommentare zaehlen wie Codebloecke nicht.

unlazy steht unter folgender Lizenz:

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

Aufruf (von bin/status.sh und bin/revise.sh):

    gates.py planned <ledger>    Issue-Text auf stdin. Exit 0 = Ledger deckt jede AC und beginnt frisch
                                 (kein Gate abgehakt, kein ABANDON); druckt dann das OWNS des Ledgers
    gates.py contract <ledger>   wie planned, ohne die Pruefung auf frischen Beginn (fuer Revisionen)
    gates.py approved            Issue-Kommentare (JSON-Liste) auf stdin. Druckt Revision, Tabulator, OWNS
                                 der hoechsten Freigabe des product-owner; Exit 1, wenn es keine gibt
    gates.py scope <owns>        Dateiliste des PR auf stdin. Exit 0 = jede Datei liegt in <owns>
    gates.py overlap [<label>]   Zeilen "<label> TAB <owns>" auf stdin (<owns> auch "@<ledger>"). Exit 0 = kein
                                 Paar ueberschneidet sich; mit <label> nur Paare, an denen dieses Label beteiligt ist
    gates.py run <ledger> <head8> <cwd> <rolle> <timeout>
                                 jedes ausfuehrbare Gate in <cwd> ausfuehren, Beleg fuer <head8> ins Ledger
    gates.py attest <ledger> <gate> <head8> <rolle> <beleg>
                                 ein manuelles Gate fuer <head8> belegen
    gates.py unmet <ledger> <head8> runnable|all
                                 Exit 0 = jedes (ausfuehrbare) Gate hat einen gueltigen Beleg fuer <head8>

Ein Beleg gilt fuer genau einen HEAD und eine Definition (CHECK, EXPECT, CWD). Ein Push oder eine
geaenderte Zeile macht ihn ungueltig. Gruen heisst: Exit 0 und EXPECT in stdout plus stderr.
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
# Eine Freigabe ist eine Zeile in einem Kommentar, dessen erste Zeile der product-owner geschrieben hat
# (bin/status.sh planned, bin/revise.sh).
APPROVAL_HEAD_RE = re.compile(r"^\*\*[^*]+\*\* — product-owner · ")
APPROVAL_LINE_RE = re.compile(r"^OWNS Revision (\d+): `([^`]+)`\s*$")


def readable_lines(text):
    """Zeilen mit Nummer, ohne eingezaeunte Codebloecke (CommonMark-Regeln) und ohne HTML-Kommentare."""
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
        return what + " ist leer"
    if v.startswith("/") or re.match(r"^[A-Za-z]:", v):
        return what + " muss relativ sein: " + v
    if ".." in v.replace("\\", "/").split("/"):
        return what + " darf kein '..' enthalten: " + v
    if v in (".", "./"):
        return what + " darf nicht die ganze Wurzel sein: " + v
    return None


def owns_error(value):
    err = relative_path_error(value, "OWNS-Pfad")
    if err:
        return err
    p = value.strip()
    p = p[2:] if p.startswith("./") else p
    if any("**" in s and s != "**" for s in p.split("/")):
        return "OWNS-Pfad: ** nur als ganzes Pfadsegment: " + value
    if not p.strip("*/?"):
        return "OWNS-Pfad gibt die ganze Wurzel frei: " + value
    return None


def compile_expect(expect):
    """EXPECT als (art, wert). /muster/flags ist ein regulaerer Ausdruck, sonst Teilstring."""
    m = REGEX_EXPECT_RE.match(expect)
    if not m:
        return ("text", expect), None
    flags = 0
    for f in m.group(2):
        if f not in REGEX_FLAGS:
            return None, "EXPECT-Flag '%s' unbekannt (erlaubt: imsu)" % f
        flags |= REGEX_FLAGS[f]
    try:
        return ("regex", re.compile(m.group(1), flags)), None
    except re.error as e:
        return None, "EXPECT ist kein gueltiger regulaerer Ausdruck: %s" % e


def parse(text):
    gates, owns, abandoned, errors = [], [], {}, []
    owns_seen, current = False, None
    for number, line in readable_lines(text):
        where = "Zeile %d: " % number
        g = GATE_RE.match(line)
        if g:
            head = GATE_HEAD_RE.match(g.group(2).strip())
            if not head:
                errors.append(where + "Gate ohne ID — Format '- [ ] AC-1: <ergebnis>'")
                current = None
                continue
            current = {"id": head.group(1), "title": head.group(2).strip(), "checked": g.group(1) != " ",
                       "check": None, "expect": None, "cwd": None, "evidence": None, "line": number,
                       "evidence_line": None, "last_line": number}
            gates.append(current)
            continue
        if INDENTED_ABANDON_RE.match(line):
            errors.append(where + "ABANDON ist eingerueckt und gilt deshalb nicht — an Spalte 1 schreiben")
            continue
        a = ATTR_RE.match(line)
        if a:
            if current is None:
                errors.append(where + a.group(2) + " steht unter keinem Gate")
                continue
            key = a.group(2).lower()
            if current[key] is not None:
                errors.append(where + "Gate %s: %s doppelt" % (current["id"], a.group(2)))
                continue
            current[key] = a.group(3).strip()
            current["last_line"] = number
            if key == "evidence":
                current["evidence_line"] = number
            continue
        if UNINDENTED_ATTR_RE.match(line):
            errors.append(where + line.split(":")[0] + " ist nicht eingerueckt und gehoert zu keinem Gate")
            continue
        ab = ABANDON_RE.match(line)
        if ab:
            gid, reason = ab.group(1), ab.group(2).strip()
            if not gid or not reason:
                errors.append(where + "ABANDON braucht eine Gate-ID und einen Grund")
            elif gid in abandoned:
                errors.append(where + "ABANDON fuer %s doppelt" % gid)
            else:
                abandoned[gid] = reason
            continue
        o = OWNS_RE.match(line)
        if o:
            if gates:
                errors.append(where + "OWNS muss vor dem ersten Gate stehen")
            elif owns_seen:
                errors.append(where + "OWNS doppelt")
            else:
                owns_seen = True
                owns = [p.strip() for p in o.group(1).split(",") if p.strip()]
                errors.extend(where + e for e in map(owns_error, owns) if e)
            continue

    if not gates:
        errors.append("Ledger ohne Gate")
    seen = set()
    for gate in gates:
        gid = gate["id"]
        if gid in seen:
            errors.append("Gate-ID %s doppelt" % gid)
        seen.add(gid)
        if (gate["check"] is None) != (gate["expect"] is None):
            errors.append("Gate %s: ein ausfuehrbares Gate braucht CHECK und EXPECT, ein manuelles keines von beiden" % gid)
        elif gate["check"] is not None and (not gate["check"] or not gate["expect"]):
            errors.append("Gate %s: CHECK und EXPECT duerfen nicht leer sein" % gid)
        elif gate["expect"]:
            gate["expectation"], err = compile_expect(gate["expect"])
            if err:
                errors.append("Gate %s: %s" % (gid, err))
        if gate["cwd"] is not None:
            err = relative_path_error(gate["cwd"], "CWD")
            if err:
                errors.append("Gate %s: %s" % (gid, err))
    for gid in abandoned:
        if gid not in seen:
            errors.append("ABANDON nennt unbekanntes Gate %s" % gid)
    return {"gates": gates, "owns": owns, "abandoned": abandoned, "errors": errors}


def issue_acs(body):
    """Jede AC-<n> im Issue-Text, in Reihenfolge und in jeder Schreibweise: Liste, Checkbox, Tabelle, Zitat."""
    acs = []
    for _, line in readable_lines(body):
        for ac in ISSUE_AC_RE.findall(line):
            if ac not in acs:
                acs.append(ac)
    return acs


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def cmd_contract(ledger_path, fresh):
    try:
        doc = parse(read(ledger_path))
    except OSError:
        print("kein Ledger unter %s — je AC ein Gate, Format in bin/gates.py" % ledger_path)
        return 1
    acs = issue_acs(sys.stdin.read())
    errors = list(doc["errors"])
    if not acs:
        errors.append("das Issue nennt keine AC — je Kriterium eine Zeile 'AC-<n>: <beobachtbares ergebnis>'")
    ids = [g["id"] for g in doc["gates"]]
    missing = [a for a in acs if a not in ids]
    if missing:
        errors.append("AC ohne Gate im Ledger: " + ", ".join(missing))
    unknown = [i for i in ids if AC_ID_RE.match(i) and acs and i not in acs]
    if unknown:
        errors.append("Ledger nennt AC, die das Issue nicht kennt: " + ", ".join(unknown))
    if not doc["owns"]:
        errors.append("Ledger ohne OWNS — welche Pfade darf dieses Ticket aendern?")
    if fresh:
        checked = [g["id"] for g in doc["gates"] if g["checked"]]
        if checked:
            errors.append("Gate schon abgehakt, bevor die Arbeit beginnt: " + ", ".join(checked))
        if doc["abandoned"]:
            errors.append("ABANDON, bevor die Arbeit beginnt: " + ", ".join(doc["abandoned"]))
    if errors:
        print(" · ".join(errors))
        return 1
    print(", ".join(doc["owns"]))
    return 0


def split_owns(value):
    return [p.strip() for p in value.split(",") if p.strip()]


def glob_regex(pattern):
    """OWNS-Glob als regulaerer Ausdruck: ** ueber Verzeichnisgrenzen, * und ? innerhalb eines Namens,
    / am Ende = alles darunter. Setzt einen Glob voraus, den owns_error zugelassen hat."""
    p = pattern.strip()
    p = p[2:] if p.startswith("./") else p
    rx = re.escape(p).replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*").replace(r"\?", "[^/]")
    return re.compile("^" + rx + (".*" if p.endswith("/") else "") + "$")


def cmd_approved():
    best = None
    for body in json.loads(sys.stdin.read() or "[]"):
        lines = body.splitlines()
        if not lines or not APPROVAL_HEAD_RE.match(lines[0]):
            continue
        for line in lines[1:]:
            m = APPROVAL_LINE_RE.match(line)
            if m and (best is None or int(m.group(1)) >= best[0]):
                best = (int(m.group(1)), m.group(2))
    if best is None:
        print("keine freigegebene OWNS-Revision am Issue — sie entsteht mit planned oder bin/revise.sh")
        return 1
    print("%d\t%s" % best)
    return 0


def cmd_scope(owns):
    globs = split_owns(owns)
    files = [f.strip() for f in sys.stdin.read().splitlines() if f.strip()]
    if not files:
        print("Dateiliste des PR ist leer — Fehlschlag, kein Zustand")
        return 1
    patterns = [glob_regex(g) for g in globs]
    outside = [f for f in files if not any(p.match(f) for p in patterns)]
    if outside:
        print("Dateien ausserhalb OWNS (%s): %s · eine Erweiterung gibt nur der product-owner frei: bin/revise.sh"
              % (", ".join(globs), ", ".join(outside)))
        return 1
    print("Umfang ok: %d Dateien" % len(files))
    return 0


def globs_overlap(a, b):
    """Koennen zwei OWNS-Globs dieselbe Datei meinen? Im Zweifel ja.
    Ein Pfad ohne Glob ist genau eine Datei: dann entscheidet, ob der andere Glob sie trifft. Sonst die
    Segment-Regel aus unlazy (globsOverlap): getrennt nur, wenn ein woertliches Segment abweicht, bevor
    auf einer Seite ein Glob-Zeichen steht."""
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
            try:
                owns = ", ".join(parse(read(owns[1:]))["owns"])
            except OSError:
                print("Ledger nicht lesbar: " + owns[1:])
                return 1
        claims.append((label, split_owns(owns)))
    conflicts = []
    for i, (la, ga) in enumerate(claims):
        for lb, gb in claims[i + 1:]:
            if only and only not in (la, lb):
                continue
            pairs = ["%s ~ %s" % (x, y) for x in ga for y in gb if globs_overlap(x, y)]
            if pairs:
                conflicts.append("%s und %s ueberschneiden sich: %s" % (la, lb, ", ".join(pairs)))
    if conflicts:
        print(" · ".join(conflicts) + " · zwei Engineers arbeiten parallel, OWNS muessen getrennt sein")
        return 1
    return 0


def definition_digest(gate):
    raw = json.dumps([gate["check"] or "", gate["expect"] or "", gate["cwd"] or ""])
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def stamp():
    return time.strftime("%Y-%m-%dT%H:%M")


def gate_problem(gate, head8):
    """None, wenn das Gate einen gueltigen Beleg fuer head8 hat, sonst der Grund."""
    evidence = gate["evidence"] or "pending"
    if gate["check"] is None:
        return None if evidence.startswith("manual head=%s " % head8) else "manuell ohne Beleg fuer diesen HEAD"
    if not evidence.startswith("v1 "):
        return "nie gruen gelaufen"
    fields = dict(f.split("=", 1) for f in evidence.split() if "=" in f)
    if fields.get("head") != head8:
        return "Beleg gilt HEAD %s" % fields.get("head", "?")
    if fields.get("def") != definition_digest(gate):
        return "Definition seit dem Lauf geaendert"
    if fields.get("exit") != "0" or fields.get("expect") != "matched":
        return "kein gruener Lauf"
    return None


def write_results(path, text, doc, results):
    """results: {gate-id: (abgehakt, evidence)}. Aendert nur Checkbox und EVIDENCE-Zeile, schreibt atomar."""
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
    doc = parse(text)
    if doc["errors"]:
        print(" · ".join(doc["errors"]))
        return 2
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
                "exit=%d, EXPECT %s" % (p.returncode, "gefunden" if matched else "nicht gefunden")
        except subprocess.TimeoutExpired:
            why = "Zeitueberschreitung nach %s s" % timeout
        except OSError as e:
            why = "nicht startbar: %s" % e
        if why is None:
            results[gate["id"]] = (True, "v1 head=%s def=%s exit=0 expect=matched out=%s at=%s by=%s" % (
                head8, definition_digest(gate), hashlib.sha256(combined.encode("utf-8")).hexdigest()[:12], stamp(), role))
            report.append("%s gruen" % gate["id"])
        else:
            results[gate["id"]] = (False, "pending")
            report.append("%s ROT: %s · %s" % (gate["id"], why, " ".join(combined.split())[-200:]))
    if not results:
        print("keine ausfuehrbaren Gates im Ledger")
        return 0
    write_results(path, text, doc, results)
    print("\n".join(report))
    return 0 if all(ok for ok, _ in results.values()) else 1


def cmd_attest(path, gid, head8, role, beleg):
    text = read(path)
    doc = parse(text)
    if doc["errors"]:
        print(" · ".join(doc["errors"]))
        return 2
    gate = next((g for g in doc["gates"] if g["id"] == gid), None)
    beleg = " ".join(beleg.split())
    problem = ("Gate %s gibt es im Ledger nicht" % gid if gate is None else
               "Gate %s ist ausfuehrbar — sein Beleg entsteht nur mit bin/gates.sh run" % gid if gate["check"] is not None else
               "Gate %s ist per ABANDON aufgegeben" % gid if gid in doc["abandoned"] else
               "ein Beleg braucht Text" if not beleg else None)
    if problem:
        print(problem)
        return 1
    write_results(path, text, doc, {gid: (True, "manual head=%s by=%s at=%s — %s" % (head8, role, stamp(), beleg))})
    print("%s belegt fuer HEAD %s" % (gid, head8))
    return 0


def cmd_unmet(path, head8, mode):
    try:
        doc = parse(read(path))
    except OSError:
        print("kein Ledger unter %s" % path)
        return 1
    if doc["errors"]:
        print(" · ".join(doc["errors"]))
        return 1
    problems = []
    for gate in doc["gates"]:
        if gate["id"] in doc["abandoned"] or (mode == "runnable" and gate["check"] is None):
            continue
        why = gate_problem(gate, head8)
        if why:
            problems.append("%s (%s)" % (gate["id"], why))
    if problems:
        print("Gates nicht gruen fuer HEAD %s: %s · ausfuehrbare mit bin/gates.sh run, manuelle mit bin/gates.sh attest"
              % (head8, ", ".join(problems)))
        return 1
    print("alle Gates gruen fuer HEAD %s" % head8)
    return 0


COMMANDS = {
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
        sys.stderr.write(__doc__.split("Aufruf")[-1])
        return 2
    return run(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
