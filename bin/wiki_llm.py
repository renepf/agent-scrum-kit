"""wiki_llm.py - the only place a model is called. `wiki.sh describe` and `wiki.sh ask` use it.

The model writes text; the script decides. Line numbers never come from the model: it picks candidate
ids, or it proposes a description plus a verbatim quote that the script then looks up in the source.
  WIKI_LLM_URL    llama-server base URL (default http://127.0.0.1:8080)
  WIKI_LLM_MODEL  model name sent in the request (default: whatever the server has loaded)
"""
import json, os, re, sys, urllib.request

URL = os.environ.get("WIKI_LLM_URL", "http://127.0.0.1:8080").rstrip("/")


def chat(system, user, max_tokens=1200):
    body = {"model": os.environ.get("WIKI_LLM_MODEL", "local"), "temperature": 0, "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    req = urllib.request.Request(URL + "/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=int(os.environ.get("WIKI_LLM_TIMEOUT", "600"))) as r:
            return json.load(r)["choices"][0]["message"]["content"]
    except Exception as e:  # a failed call is a failure, never an answer
        raise SystemExit(f"model call failed ({URL}): {e}")


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def pick_ids(system, user, valid, limit):
    """Ask for `IDS: 3,7`; only ids from `valid` survive. Returns [] when the model names none."""
    out = chat(system, user, 120)
    m = re.search(r"IDS:\s*([\d,\s]+)", out)
    ids = [int(x) for x in re.findall(r"\d+", m.group(1))] if m else []
    seen, res = set(), []
    for i in ids:
        if i in valid and i not in seen:
            seen.add(i); res.append(i)
    return res[:limit]
