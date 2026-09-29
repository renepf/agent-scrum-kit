#!/usr/bin/env python3
"""Stub of llama-server for eval cases: answers /v1/chat/completions from fixed rules. Prints the port."""
import http.server, json, re, sys

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        sysm, user = req["messages"][0]["content"], req["messages"][1]["content"]
        if "route questions" in sysm:
            out = "IDS: 0"
        elif "pick the code location" in sysm:
            ids = [l.split(".")[0] for l in user.split("\n") if re.match(r"^\d+\. ", l) and "login" in l.lower()]
            out = "IDS: " + (ids[0] if ids else "99")
        else:
            out = "0|Anmeldung der Nutzer|fun login(user: String)\n1|Holt ein neues Token|token = refresh(user)\n2|Erfundene Zeile|this text is not in the source\n"
        body = json.dumps({"choices": [{"message": {"content": out}}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)

srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
