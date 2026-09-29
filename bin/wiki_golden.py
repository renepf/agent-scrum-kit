"""wiki_golden.py - `wiki.sh golden <golden.json>`: run each question through `wiki.sh ask`, score strictly.

Rule (owner D72, strict; our operationalisation is question Q1 of the handover):
a question counts only when an answer names the expected file AND a line range that overlaps the expected
range and is not larger than max(3 x expected length, 40) lines. A file without lines, a partial hit
(right file, no overlap), a whole-file citation, or no citation is a miss.
The golden file lives OUTSIDE the wiki; the librarian never reads it.
"""
import json, os, re, subprocess, sys

CITE = re.compile(r"answer: ([A-Za-z0-9_-]+):(.+?):(\d+)-(\d+)@([0-9a-f]{7,40})")


def hit(cites, exp):
    for tag, path, a, b, _ in cites:
        if not path.endswith(exp["path_suffix"]) or tag != exp["side"]:
            continue
        a, b = int(a), int(b)
        ea, eb = exp["a"], exp["b"]
        if a <= eb and b >= ea and (b - a + 1) <= max(3 * (eb - ea + 1), 40):
            return True
    return False


def run(golden_path, wiki_sh):
    qs = json.load(open(golden_path, encoding="utf-8"))
    passed = 0
    for q in qs:
        r = subprocess.run([wiki_sh, "ask", q["question"]], capture_output=True, text=True)
        if r.returncode:
            print(f"BLOCK {q['id']}: ask failed: {r.stderr.strip()[:160]}")
            continue
        cites = CITE.findall(r.stdout)
        ok = any(hit(cites, e) for e in q["expected"])
        passed += ok
        why = "" if ok else f"  expected {q['expected'][0]['side']}:{q['expected'][0]['path_suffix']}:{q['expected'][0]['a']}-{q['expected'][0]['b']}, got {[c[1].split('/')[-1] + ':' + c[2] + '-' + c[3] for c in cites] or r.stdout.strip()[:80]}"
        print(f"{'PASS' if ok else 'MISS'} {q['id']}{why}")
    n = len(qs)
    print(f"golden: {passed}/{n} = {100 * passed / n:.0f} %" if n else "golden: no questions")
    sys.exit(0 if n and passed == n else 1)
