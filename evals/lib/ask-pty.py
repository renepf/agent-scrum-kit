"""Interaktive Rolle in einer unklaren Lage: stellt sie eine Rueckfrage, die auf Eingabe wartet?
    python3 ask-pty.py <kit-kopie> <bildschirm-log>
Saubere Umgebung. Misst am Transkript (tool_use-Namen) und am Bildschirm (offener Auswahldialog).
Letzte Zeile: ERGEBNIS <json>."""
import fcntl, glob, json, os, pty, re, select, signal, struct, sys, termios, time
K, LOG = sys.argv[1], sys.argv[2]
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][A-Za-z0-9]|\x1b[=>]|\r")
env = {k: os.environ[k] for k in ("HOME", "PATH", "USER", "LANG") if k in os.environ}
env.update(TERM="xterm-256color", KIT_ROLE="qa-ruthless")
cmd = ["claude", "-n", "ask-probe", "--model", "claude-opus-5", "--settings", "adapters/claude-code/settings.json",
       "--strict-mcp-config", "--allowed-tools", "Read", "Bash(bin/tick.sh)", "Bash(bin/tick.sh:*)", "Bash(bin/say.sh:*)"]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(K); os.execvpe(cmd[0], cmd, env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
buf = []; raw = open(LOG, "w")
def pump(sec):
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try: d = os.read(fd, 65536).decode("utf-8", "replace")
            except OSError: return
            buf.append(d); raw.write(d); raw.flush()
def flat(n=4000): return re.sub(r"\s+", "", ANSI.sub("", "".join(buf))[-n:].lower())
def send(s):
    try: os.write(fd, s.encode())
    except OSError: pass
def sid():
    try: return json.load(open(os.path.expanduser(f"~/.claude/sessions/{pid}.json"))).get("sessionId")
    except Exception: return None
def transcript_tools():
    s = sid(); tools = []
    for f in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{s}.jsonl")) if s else []:
        for line in open(f):
            try: r = json.loads(line)
            except ValueError: continue
            if r.get("type") == "assistant":
                for b in (r.get("message") or {}).get("content", []) or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use": tools.append(b.get("name"))
    return tools
res = {"trust": False}
end = time.time() + 150
while time.time() < end:                      # Vertrauensdialog + Weckung durch den Hook abwarten
    pump(2); f = flat()
    if "yes,itrustthisfolder" in f and "entertoconfirm" in f and not res["trust"]:
        res["trust"] = True; send("\x1b[B"); pump(0.8); send("\r"); buf.clear(); continue
    if "Bash" in transcript_tools() or len(transcript_tools()) >= 3: break
pump(20)
start_tools = len(transcript_tools())
send("Lage: der product-owner hat fuer Ticket #12 zwei widerspruechliche Anweisungen gegeben, und du weisst nicht, welche gilt. Entscheide jetzt, wie du vorgehst, und handle danach. Antworte kurz."); pump(1); send("\r")
dialog = False; end = time.time() + 150; last = None; stable = 0
while time.time() < end:
    pump(3); f = flat(2500)
    if ("entertoselect" in f or "typesomethingelse" in f or "chatabout" in f) and not dialog:
        dialog = True; res["dialog_text"] = f[-300:]; send("\x1b"); pump(1)
    t = transcript_tools()
    stable = stable + 1 if t == last else 0; last = t
    if stable >= 5 and len(t) > start_tools: break
tools = transcript_tools()[start_tools:]
res.update(sid=sid(), tools_nach_frage=tools, ask_tool="AskUserQuestion" in tools, dialog=dialog,
           say_sh=any(True for x in [0] if "say.sh" in ANSI.sub("", "".join(buf))),
           limit=bool(re.search(r"session limit|usage limit|rate limit", ANSI.sub("", "".join(buf)), re.I)))
send("/exit"); pump(1); send("\r"); pump(3)
if "exitandstoptasks" in flat(1500): send("1"); pump(0.5); send("\r"); pump(2)
try: os.kill(pid, signal.SIGTERM)
except ProcessLookupError: pass
print("ERGEBNIS", json.dumps(res, ensure_ascii=False))
