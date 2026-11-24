#!/usr/bin/env python3
"""wiki_route.py - Laya decision gate in front of `wiki.sh ask` / `brief`. Runs with the Python that has `laya` installed.

  python wiki_route.py --serve [PORT]     tiny HTTP server, POST {"q": "..."} -> {"feature","kind","side", "*_p"}; bad body -> 400
  python wiki_route.py "<question>"       one-shot, prints the same JSON
  --model DIR   trained checkpoint (env WIKI_LAYA_MODEL); default base Laya (convaiinnovations/laya, subfolder multilingual)
  --base        base Laya even if WIKI_LAYA_MODEL is set, for the baseline
  --questions F questions.py with a dict Q (default env WIKI_ROUTE_QUESTIONS): the single source of the
                question block and of the feature, kind and side labels. Required, no copy lives here.

Laya answers the typed `choice` questions of questions.py in one forward pass (no text generation); only argmax and its
probability are returned per axis. Source: github.com/NandhaKishorM/laya (Apache-2.0).
"""
import argparse, http.server, importlib.util, json, os

QUESTIONS = MODEL = _agent = None


def route(q):
    global _agent
    if _agent is None:
        import laya
        _agent = laya.load(os.path.expanduser(MODEL)) if MODEL else laya.load("convaiinnovations/laya", subfolder="multilingual")
    a = _agent.predict(q, QUESTIONS)["answers"]
    out = {}
    for ax in ("feature", "kind", "side"):
        out[ax] = a[ax]["choice"]; out[ax + "_p"] = round(a[ax]["probabilities"][a[ax]["choice"]], 4)
    return out


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        try:
            q = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)))["q"]
            if not isinstance(q, str) or not q.strip(): raise TypeError
        except (ValueError, KeyError, TypeError):
            return self.reply(400, {"error": 'body must be JSON {"q": "<question>"}'})
        self.reply(200, route(q))


def main():
    global QUESTIONS, MODEL
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", nargs="?", const=8771, type=int, metavar="PORT")
    ap.add_argument("--model", default=os.environ.get("WIKI_LAYA_MODEL"))
    ap.add_argument("--base", action="store_true")
    ap.add_argument("--questions", default=os.environ.get("WIKI_ROUTE_QUESTIONS"))
    ap.add_argument("question", nargs="*")
    args = ap.parse_args()
    if not args.questions:
        ap.error("--questions (or WIKI_ROUTE_QUESTIONS) is required: path to questions.py")
    spec = importlib.util.spec_from_file_location("questions", os.path.expanduser(args.questions))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    QUESTIONS, MODEL = mod.Q, None if args.base else args.model
    if args.serve is None:
        return print(json.dumps(route(" ".join(args.question))))
    route("warmup")
    print(f"wiki_route serving on 127.0.0.1:{args.serve}", flush=True)
    http.server.HTTPServer(("127.0.0.1", args.serve), H).serve_forever()


if __name__ == "__main__":
    main()
