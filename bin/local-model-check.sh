#!/usr/bin/env bash
# Measures every model a local OpenAI-compatible endpoint serves: does it return a structured tool call?
# A role needs tool calls to run bin/*.sh. A "tools" badge or capability list is not a measurement: on
# 2026-09-15 Ollama listed "tools" for qwen2.5-coder:14b, and the model answered 6 of 6 tool requests with
# the call as plain JSON text (tool_calls null).
#
#   bin/local-model-check.sh     table for all models; exit 0 only if KIT_LOCAL_MODEL is set and passed
#
# kit.env: KIT_LOCAL_BASE_URL (e.g. http://127.0.0.1:11434/v1), KIT_LOCAL_MODEL (your choice from the table).
# A failed request is UNKNOWN, never "no". Nothing is picked for you.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ -n "${KIT_LOCAL_BASE_URL:-}" ] || die "KIT_LOCAL_BASE_URL is not set in kit.env (e.g. http://127.0.0.1:11434/v1)"

python3 - "$KIT_LOCAL_BASE_URL" "${KIT_LOCAL_MODEL:-}" "${KIT_LOCAL_CHECK_TIMEOUT:-600}" <<'PY'
import json, sys, urllib.error, urllib.request

base, chosen, timeout = sys.argv[1].rstrip("/"), sys.argv[2], float(sys.argv[3])

def call(path, body=None):
    req = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer local"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)

def reason(e):
    if isinstance(e, urllib.error.HTTPError):
        return "HTTP %d" % e.code
    return str(getattr(e, "reason", e))

TOOL = {"type": "function", "function": {
    "name": "report_status", "description": "Report the current status.",
    "parameters": {"type": "object", "properties": {"status": {"type": "string"}}, "required": ["status"]}}}

def tool_call(model):
    try:
        r = call("/chat/completions", {"model": model, "tools": [TOOL], "messages": [
            {"role": "user", "content": "Call the tool report_status with status set to ready."}]})
    except Exception as e:
        return "UNKNOWN — request failed: %s" % reason(e)
    try:
        msg = r["choices"][0]["message"]
    except (KeyError, IndexError, TypeError):
        return "UNKNOWN — answer without choices[0].message"
    names = [(c.get("function") or {}).get("name") for c in msg.get("tool_calls") or []]
    if "report_status" in names:
        return "yes"
    if names:
        return "no (called %s)" % ", ".join(map(str, names))
    return "no (answer came back as text)"

try:
    models = [m["id"] for m in call("/models")["data"]]
except Exception as e:
    print("endpoint %s: UNKNOWN — model list not readable: %s" % (base, reason(e)))
    sys.exit(1)

def loaded(model):
    """Ollama only (measured 0.34.0): /api/ps names size, size_vram and context_length of a loaded model."""
    if not base.endswith("/v1"):
        return "memory: UNKNOWN — no Ollama /api/ps next to this endpoint"
    try:
        req = urllib.request.Request(base[:-3] + "/api/ps")
        with urllib.request.urlopen(req, timeout=10) as r:
            rows = [x for x in json.load(r).get("models", []) if x.get("name") == model]
    except Exception as e:
        return "memory: UNKNOWN — /api/ps not readable: %s" % reason(e)
    if not rows:
        return "memory: UNKNOWN — not loaded after the request"
    x, gb = rows[0], 1024 ** 3
    return "loaded %.1f GiB, on GPU %.1f GiB, context served %s" % (
        x.get("size", 0) / gb, x.get("size_vram", 0) / gb, x.get("context_length", "UNKNOWN"))

print("endpoint %s · %d model(s)" % (base, len(models)))
results = {}
for m in models:
    results[m] = tool_call(m)
    print("  %s  tool calls: %s · %s" % (m, results[m], loaded(m)))

if not chosen:
    print("KIT_LOCAL_MODEL is not set: pick a model with 'tool calls: yes' and name it in kit.env")
    sys.exit(1)
if chosen not in results:
    print("KIT_LOCAL_MODEL=%s: refused — the endpoint does not serve it" % chosen)
    sys.exit(1)
if results[chosen] != "yes":
    print("KIT_LOCAL_MODEL=%s: refused — tool calls: %s" % (chosen, results[chosen]))
    sys.exit(1)
print("KIT_LOCAL_MODEL=%s: ok" % chosen)
PY
