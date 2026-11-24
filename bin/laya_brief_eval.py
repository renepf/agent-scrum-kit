#!/usr/bin/env python3
"""laya_brief_eval.py - `wiki.sh brief` three ways: triage-ft route, base-Laya route, lexical only (no Laya).

  python laya_brief_eval.py <questions.json> --questions <questions.py> [--wiki DIR] [--ft DIR] [--out results.json]
Run with the Python that has `laya` installed (it starts bin/wiki_route.py servers with the same interpreter, one at a time).
questions.json: list of {id, role, question, ticket, expect_topic, expect_file, expect_lines (optional [a,b])}.
Per system: topic hit (Top-1 = topic line of the brief; lexical has none), file hit (expect_file is in the brief),
line hit (a cited range of that file overlaps expect_lines; only rows that give expect_lines). File match is by relative path (folder + file).
"""
import argparse, collections, json, os, re, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("cases"); ap.add_argument("--questions", required=True)
ap.add_argument("--wiki", default="wiki"); ap.add_argument("--ft", default=os.environ.get("WIKI_LAYA_MODEL")); ap.add_argument("--out", default="brief_eval.json")
args = ap.parse_args()
cases = json.load(open(args.cases, encoding="utf-8"))


def bad(msg): print("laya_brief_eval: " + msg, file=sys.stderr); sys.exit(2)


if not cases: bad("no cases")
if not os.path.isdir(args.wiki): bad("--wiki is not a directory: " + args.wiki)
if not any(f.endswith(".md") and f not in ("index.md", "log.md") for _, _, fs in os.walk(args.wiki) for f in fs): bad("--wiki has no concept files: " + args.wiki)
for i, c in enumerate(cases):
    cid = c.get("id", "#%d" % i) if isinstance(c, dict) else "#%d" % i
    miss = [k for k in ("id", "role", "question", "expect_topic", "expect_file") if not isinstance(c, dict) or k not in c]
    if miss: bad("case %s: missing key %s" % (cid, ", ".join(miss)))
    if "/" not in c["expect_file"]: bad("case %s: expect_file needs a folder (folder/file): %s" % (cid, c["expect_file"]))
    el = c.get("expect_lines")
    if el is not None and not (isinstance(el, list) and len(el) == 2 and all(type(v) is int for v in el) and el[0] <= el[1]):
        bad("case %s: expect_lines must be null or [a, b] ints with a <= b: %s" % (cid, el))
CITE = re.compile(r"-> {2}\S+?:(\S+):(\d+)-(\d+)@")


def brief(q, url=None):
    env = {k: v for k, v in os.environ.items() if k != "WIKI_ROUTE_URL"} | {"WIKI_ROOT": os.path.abspath(args.wiki)} | ({"WIKI_ROUTE_URL": url} if url else {})
    r = subprocess.run([sys.executable, os.path.join(HERE, "wiki.py"), "brief", q], env=env, capture_output=True, text=True)
    if r.returncode: sys.exit("wiki.py brief failed (exit %d): %s" % (r.returncode, r.stderr.strip()))
    return r.stdout


def score(c, out):
    m = re.search(r"^topic: (\w+)", out, re.M)
    b = c["expect_file"]
    d, fn = b.split("/")[-2:]  # concept names carry the last folder and the file: <tag>-<folder>__<file>.md
    rels = [os.path.basename(l[2:].split(" [")[0]).partition("__") for l in out.splitlines() if l.startswith("- ")]
    cites = [(p, int(x), int(y)) for p, x, y in CITE.findall(out)]
    r = {"topic": m.group(1) if m else None, "topic_hit": (m.group(1) == c["expect_topic"]) if m else None,
         "file_hit": any(t.split("-", 1)[-1] == d and f in (fn, fn + ".md") for t, _, f in rels) or any(f == b for f, _, _ in cites), "line_hit": None}
    if c.get("expect_lines"):
        a, z = c["expect_lines"]
        r["line_hit"] = any(f == b and x <= z and y >= a for f, x, y in cites)
    return r


def serve(extra):
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "wiki_route.py"), "--questions", args.questions, "--serve", str(port)] + extra,
                         stdout=subprocess.DEVNULL)
    for _ in range(150):
        try: socket.create_connection(("127.0.0.1", port), 1).close(); return p, f"http://127.0.0.1:{port}"
        except OSError:
            if p.poll() is not None: break
            time.sleep(2)
    p.kill(); sys.exit("route server did not come up: " + " ".join(extra))


res = {}
runs = ([("triage-ft", ["--model", os.path.expanduser(args.ft)])] if args.ft else []) + [("base-laya", ["--base"]), ("lexical", None)]
if not args.ft: print("no fine-tuned model given, triage-ft row skipped")
for name, extra in runs:
    p, url = serve(extra) if extra is not None else (None, None)
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
