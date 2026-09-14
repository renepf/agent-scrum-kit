import json, subprocess, sys, time, select, os
cmd = sys.argv[1:]
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
def send(o): p.stdin.write(json.dumps(o) + "\n"); p.stdin.flush()
def recv(t=40):
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if r:
            line = p.stdout.readline()
            if not line: break
            try: return json.loads(line)
            except ValueError: continue
        if p.poll() is not None: break
    return None
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"kit-probe","version":"0"}}})
init = recv()
if not init:
    err = p.stderr.read()[:400] if p.poll() is not None else "(laeuft, keine Antwort)"
    print("KEIN INITIALIZE:", err); p.kill(); sys.exit(1)
info = init.get("result", {}).get("serverInfo", {})
send({"jsonrpc":"2.0","method":"notifications/initialized"})
send({"jsonrpc":"2.0","id":2,"method":"tools/list"})
tl = recv()
tools = [t["name"] for t in (tl or {}).get("result", {}).get("tools", [])]
desc = sum(len(t.get("description","")) for t in (tl or {}).get("result", {}).get("tools", []))
print(f"serverInfo={info.get('name')} {info.get('version')} · protokoll={init.get('result',{}).get('protocolVersion')} · {len(tools)} tools · beschreibungen {desc} zeichen")
print("  tools:", ", ".join(tools[:14]) + (" …" if len(tools) > 14 else ""))
p.kill()
