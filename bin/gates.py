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
references/gates.md und scripts/gate-lint.mjs) und hier in Python neu umgesetzt. Abweichung vom
Original: Gate-IDs, die wie ein Acceptance-Kriterium aussehen (AC-<n>), muessen im Issue stehen.

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

Aufruf (von bin/status.sh und bin/merge.sh, nicht von Hand noetig):

    gates.py planned <ledger>      Issue-Text auf stdin; Exit 0 = Ledger deckt jede AC, sonst Liste
"""
import re
import sys

GATE_RE = re.compile(r"^- \[([ xX])\]\s*(.*)$")
GATE_HEAD_RE = re.compile(r"^(\S+?):\s*(.*)$")
ATTR_RE = re.compile(r"^(\s+)(CHECK|EXPECT|EVIDENCE|CWD):\s?(.*)$")
UNINDENTED_ATTR_RE = re.compile(r"^(CHECK|EXPECT|EVIDENCE|CWD):")
ABANDON_RE = re.compile(r"^ABANDON:\s*(\S*)\s*(.*)$")
INDENTED_ABANDON_RE = re.compile(r"^\s+ABANDON:")
OWNS_RE = re.compile(r"^OWNS:\s*(.*)$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
AC_ID_RE = re.compile(r"^AC-\d+$")
ISSUE_AC_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)?(?:\*\*)?(AC-\d+)(?:\*\*)?\s*:\s*(\S.*)$")
REGEX_EXPECT_RE = re.compile(r"^/(.+)/([a-z]*)$")
REGEX_FLAGS = {"i": re.I, "m": re.M, "s": re.S, "u": 0}


def unfenced(text):
    """Zeilen mit Nummer, ohne den Inhalt eingezaeunter Codebloecke (CommonMark-Regeln)."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        m = FENCE_RE.match(line)
        if fence is None:
            if m:
                fence = m.group(1)
                continue
            yield number, line
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
            fence = None


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


def compile_expect(expect):
    """EXPECT als (art, wert). /muster/flags ist ein regulaerer Ausdruck, sonst Teilstring."""
    m = REGEX_EXPECT_RE.match(expect)
    if not m:
        return ("text", expect), None
    flags = 0
    for f in m.group(2):
        if f not in REGEX_FLAGS:
            return None, "EXPECT-Flag '%s' unbekannt (erlaubt: ims)" % f
        flags |= REGEX_FLAGS[f]
    try:
        return ("regex", re.compile(m.group(1), flags)), None
    except re.error as e:
        return None, "EXPECT ist kein gueltiger regulaerer Ausdruck: %s" % e


def parse(text):
    gates, owns, abandoned, errors = [], None, {}, []
    current = None
    for number, line in unfenced(text):
        where = "Zeile %d: " % number
        g = GATE_RE.match(line)
        if g:
            head = GATE_HEAD_RE.match(g.group(2).strip())
            if not head or not head.group(1):
                errors.append(where + "Gate ohne ID — Format '- [ ] AC-1: <ergebnis>'")
                current = None
                continue
            current = {"id": head.group(1), "title": head.group(2).strip(), "checked": g.group(1) != " ",
                       "check": None, "expect": None, "cwd": None, "evidence": None, "line": number}
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
            elif owns is not None:
                errors.append(where + "OWNS doppelt")
            else:
                owns = [p.strip() for p in o.group(1).split(",") if p.strip()]
                if not owns:
                    errors.append(where + "OWNS nennt keinen Pfad")
                for p in owns:
                    err = relative_path_error(p, "OWNS-Pfad")
                    if err:
                        errors.append(where + err)
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
    return {"gates": gates, "owns": owns or [], "abandoned": abandoned, "errors": errors}


def issue_acs(body):
    """AC-IDs aus dem Issue-Text, in Reihenfolge. Eine AC ist eine Zeile 'AC-<n>: <text>'."""
    acs, errors = {}, []
    for _, line in unfenced(body):
        m = ISSUE_AC_RE.match(line)
        if m:
            if m.group(1) in acs:
                errors.append("Issue nennt %s doppelt" % m.group(1))
            acs.setdefault(m.group(1), m.group(2).strip())
    return acs, errors


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def cmd_planned(ledger_path):
    doc = parse(read(ledger_path))
    acs, errors = issue_acs(sys.stdin.read())
    errors = doc["errors"] + errors
    if not acs:
        errors.append("das Issue nennt keine AC — je Kriterium eine Zeile 'AC-<n>: <beobachtbares ergebnis>'")
    ids = [g["id"] for g in doc["gates"]]
    missing = [a for a in acs if a not in ids]
    if missing:
        errors.append("AC ohne Gate im Ledger: " + ", ".join(missing))
    unknown = [i for i in ids if AC_ID_RE.match(i) and acs and i not in acs]
    if unknown:
        errors.append("Ledger nennt AC, die das Issue nicht kennt: " + ", ".join(unknown))
    if errors:
        print(" · ".join(errors))
        return 1
    print("Ledger deckt %d AC mit %d Gates" % (len(acs), len(ids)))
    return 0


def main(argv):
    if len(argv) == 2 and argv[0] == "planned":
        return cmd_planned(argv[1])
    sys.stderr.write(__doc__.split("Aufruf")[1] if "Aufruf" in __doc__ else "")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
