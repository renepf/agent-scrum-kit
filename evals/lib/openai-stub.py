#!/usr/bin/env python3
"""Stub of an OpenAI-compatible endpoint for static cases. Writes its port to argv[1], serves until killed.

Models:
  tool-ok    answers a tools request with a structured tool call
  text-only  answers with the call as JSON text, tool_calls absent, finish_reason stop. Measured 2026-09-15:
             Ollama 0.34.0 with qwen2.5-coder:14b answered 6 of 6 tools requests like this.
  broken     HTTP 500
"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/v1/models":
            return self.send(200, {"object": "list", "data": [{"id": m} for m in ("tool-ok", "text-only", "broken")]})
        self.send(404, {})

    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        model, tools = req.get("model"), req.get("tools") or []
        if model == "broken":
            return self.send(500, {"error": "boom"})
        name = tools[0]["function"]["name"] if tools else "none"
        if model == "tool-ok":
            msg = {"role": "assistant", "content": "", "tool_calls": [{"id": "c1", "type": "function",
                   "function": {"name": name, "arguments": "{\"status\": \"ready\"}"}}]}
            fin = "tool_calls"
        else:
            msg = {"role": "assistant", "content": json.dumps({"name": name, "arguments": {"status": "ready"}})}
            fin = "stop"
        self.send(200, {"choices": [{"index": 0, "message": msg, "finish_reason": fin}]})


s = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
