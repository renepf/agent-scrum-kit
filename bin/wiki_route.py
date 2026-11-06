#!/usr/bin/env python3
"""wiki_route.py - Laya decision gate in front of `wiki.sh ask`. Runs with the Python that has `laya` installed.

  python wiki_route.py --serve [PORT]     tiny HTTP server, POST {"q": "..."} -> {"kind", "side", "kind_p", "side_p"}
  python wiki_route.py "<question>"       one-shot, prints the same JSON

Laya answers two typed `choice` questions in one forward pass (no text generation):
  kind  code | requirement | ticket      what kind of source answers the question
  side  ios | android | none             which platform the question names
Only the argmax and its probability are returned; the caller decides what to do with them.
Checkpoint: convaiinnovations/laya, subfolder multilingual (German questions). Source: github.com/NandhaKishorM/laya (Apache-2.0).
"""
import json, sys

QUESTIONS = {
    "kind": {"type": "choice", "instructions": "Welche Art von Quelle beantwortet die Frage?", "criteria": {
        "code": "Die Frage sucht eine Stelle im Quellcode: wo wird etwas gemacht, welche Datei, welche Funktion, welche Zeile",
        "requirement": "Die Frage sucht eine Anforderung, eine Spezifikation oder eine Regel des Produkts",
        "ticket": "Die Frage sucht ein Ticket, eine Entscheidung, einen Auftrag oder den Projektstand"}},
    "side": {"type": "choice", "instructions": "Welche Plattform nennt die Frage ausdruecklich?", "criteria": {
        "ios": "iOS, Swift, iPhone oder Apple wird genannt",
        "android": "Android, Kotlin, Compose oder Google wird genannt",
        "none": "keine Plattform wird genannt"}},
}
_agent = None


def route(q):
    global _agent
    if _agent is None:
        import laya
        _agent = laya.load("convaiinnovations/laya", subfolder="multilingual")
    a = _agent.predict(q, QUESTIONS)["answers"]
    k, s = a["kind"], a["side"]
    return {"kind": k["choice"], "kind_p": round(k["probabilities"][k["choice"]], 4),
            "side": s["choice"], "side_p": round(s["probabilities"][s["choice"]], 4)}


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--serve":
        import http.server
        port = int(sys.argv[2]) if len(sys.argv) > 2 else 8771

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_POST(self):
                q = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["q"]
                body = json.dumps(route(q)).encode()
                self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
        route("warmup")
        print(f"wiki_route serving on 127.0.0.1:{port}", flush=True)
        http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
    else:
        print(json.dumps(route(" ".join(sys.argv[1:]))))
