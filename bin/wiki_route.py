#!/usr/bin/env python3
"""wiki_route.py - Laya decision gate in front of `wiki.sh ask` / `brief`. Runs with the Python that has `laya` installed.

  python wiki_route.py --serve [PORT]     tiny HTTP server, POST {"q": "..."} -> {"feature","kind","side", "*_p"}
  python wiki_route.py "<question>"       one-shot, prints the same JSON
  --model DIR   fine-tuned checkpoint (default ~/models/laya/triage-ft, env WIKI_LAYA_MODEL)
  --base        serve base Laya (convaiinnovations/laya, subfolder multilingual) instead, for the baseline
  --questions F questions.py with a dict Q (default env WIKI_ROUTE_QUESTIONS): the single source of the
                question block, the same one the fine-tune rows carry. Required, no copy lives here.

Laya answers three typed `choice` questions in one forward pass (no text generation); only argmax and its
probability are returned. kind code|requirement|ticket, side ios|android|both|none, feature auth|sales|parity|other
(feature "other" matches no wiki topic: `brief` then prints "no concept"). Source: github.com/NandhaKishorM/laya (Apache-2.0).
"""
import argparse, importlib.util, json, os

ap = argparse.ArgumentParser()
ap.add_argument("--serve", nargs="?", const=8771, type=int, metavar="PORT")
ap.add_argument("--model", default=os.environ.get("WIKI_LAYA_MODEL", "~/models/laya/triage-ft"))
ap.add_argument("--base", action="store_true")
ap.add_argument("--questions", default=os.environ.get("WIKI_ROUTE_QUESTIONS"))
ap.add_argument("question", nargs="*")
args = ap.parse_args()
if not args.questions:
    ap.error("--questions (or WIKI_ROUTE_QUESTIONS) is required: path to questions.py")
_spec = importlib.util.spec_from_file_location("questions", os.path.expanduser(args.questions))
QUESTIONS = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(QUESTIONS); QUESTIONS = QUESTIONS.Q
_agent = None


def route(q):
    global _agent
    if _agent is None:
        import laya
        _agent = laya.load("convaiinnovations/laya", subfolder="multilingual") if args.base else laya.load(os.path.expanduser(args.model))
    a = _agent.predict(q, QUESTIONS)["answers"]
    out = {}
    for ax in ("feature", "kind", "side"):
        out[ax] = a[ax]["choice"]; out[ax + "_p"] = round(a[ax]["probabilities"][a[ax]["choice"]], 4)
    return out


if args.serve is not None:
    import http.server

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_POST(self):
            q = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["q"]
            body = json.dumps(route(q)).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    route("warmup")
    print(f"wiki_route serving on 127.0.0.1:{args.serve}", flush=True)
    http.server.HTTPServer(("127.0.0.1", args.serve), H).serve_forever()
else:
    print(json.dumps(route(" ".join(args.question))))
