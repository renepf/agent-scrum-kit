#!/usr/bin/env python3
"""laya_brief_eval.py - `wiki.sh brief` three ways: triage-ft route, base-Laya route, lexical only (no Laya).

  python laya_brief_eval.py <questions.json> --questions <questions.py> [--wiki DIR] [--ft DIR] [--out results.json]
Run with the Python that has `laya` installed (it starts bin/wiki_route.py servers with the same interpreter, one at a time).
questions.json: list of {id, role, question, ticket, expect_topic, expect_file, expect_lines (optional [a,b])}.
Per system: topic hit (Top-1 = topic line of the brief; lexical has none), file hit (expect_file is in the brief),
line hit (a cited range of that file overlaps expect_lines; only rows that give expect_lines). File match is by base name.
"""
import argparse, collections, json, os, re, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("cases"); ap.add_argument("--questions", required=True)
ap.add_argument("--wiki", default="wiki"); ap.add_argument("--ft", default="~/models/laya/triage-ft"); ap.add_argument("--out", default="brief_eval.json")
args = ap.parse_args()
cases = json.load(open(args.cases, encoding="utf-8"))
CITE = re.compile(r"-> {2}\S+?:(\S+):(\d+)-(\d+)@")


def brief(q, url=None):
    env = dict(os.environ, WIKI_ROOT=os.path.abspath(args.wiki), WIKI_BRIEF_TOP=os.environ.get("WIKI_BRIEF_TOP", "8"))
    env.pop("WIKI_ROUTE_URL", None)
    if url: env["WIKI_ROUTE_URL"] = url
    return subprocess.run([sys.executable, os.path.join(HERE, "wiki.py"), "brief", q], env=env, capture_output=True, text=True).stdout


def score(c, out):
    m = re.search(r"^topic: (\w+)", out, re.M)
    b = os.path.basename(c["expect_file"])
    rels = [os.path.basename(l[2:].split(" [")[0]) for l in out.splitlines() if l.startswith("- ")]
    cites = [(os.path.basename(p), int(x), int(y)) for p, x, y in CITE.findall(out)]
    r = {"topic": m.group(1) if m else None, "topic_hit": (m.group(1) == c["expect_topic"]) if m else None,
         "file_hit": any(x.endswith("__" + b + ".md") or x == b + ".md" for x in rels) or any(f == b for f, _, _ in cites), "line_hit": None}
    if c.get("expect_lines"):
        a, z = c["expect_lines"]
        r["line_hit"] = any(f == b and x <= z and y >= a for f, x, y in cites)
    return r


def serve(extra):
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "wiki_route.py"), "--questions", args.questions, "--serve", str(port)] + extra,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(150):
        try: socket.create_connection(("127.0.0.1", port), 1).close(); return p, f"http://127.0.0.1:{port}"
        except OSError:
            if p.poll() is not None: break
            time.sleep(2)
    p.kill(); sys.exit("route server did not come up: " + " ".join(extra))


res = {}
for name, extra in (("triage-ft", ["--model", args.ft]), ("base-laya", ["--base"]), ("lexical", None)):
    p, url = serve(extra) if extra else (None, None)
    try: res[name] = [dict(id=c["id"], role=c["role"], **score(c, brief(c["question"], url))) for c in cases]
    finally:
        if p: p.terminate(); p.wait()


def pct(rows, k):
    v = [r[k] for r in rows if r[k] is not None]
    return "%3d/%-3d %4.0f%%" % (sum(v), len(v), 100 * sum(v) / len(v)) if v else "   n/a"


print("%-10s %-14s %-14s %-14s" % ("", "topic Top-1", "file in brief", "file+lines"))
for name, rows in res.items():
    print("%-10s %-14s %-14s %-14s  (all roles, n=%d)" % (name, pct(rows, "topic_hit"), pct(rows, "file_hit"), pct(rows, "line_hit"), len(rows)))
    by = collections.defaultdict(list)
    for r in rows: by[r["role"]].append(r)
    for role, rr in sorted(by.items()):
        print("  %-8s %-14s %-14s %-14s  (n=%d)" % (role, pct(rr, "topic_hit"), pct(rr, "file_hit"), pct(rr, "line_hit"), len(rr)))
json.dump(res, open(args.out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print("per-question results:", args.out)
