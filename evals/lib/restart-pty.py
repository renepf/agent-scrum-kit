"""Echter Neustart unter adapters/claude-code/role-loop.sh.
Die Rolle schreibt ihre Uebergabe und ruft selbst bin/restart-self.sh stop. Gemessen wird, ob die
Schleife claude neu startet, der Weck-Hook die neue Session in die Rolle bringt und sie sich mit neuer
PID und neuer Session-ID registriert. Saubere Umgebung (env -i-Aequivalent)."""
import fcntl, glob, json, os, pty, re, select, signal, struct, sys, termios, time
K, LOG = sys.argv[1], sys.argv[2]
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][A-Za-z0-9]|\x1b[=>]|\r")
ROLE = "engineer-a"
env = {k: os.environ[k] for k in ("HOME", "PATH", "USER", "LANG") if k in os.environ}
env["TERM"] = "xterm-256color"
# Der Kommando-Ersatz fuegt nur Modell, strikte MCP-Liste und Freigaben fuer die drei Kit-Skripte hinzu,
# damit keine Permission-Abfrage den Test blockiert. Alles andere ist der Standardbefehl der Schleife.
env["KIT_LOOP_CLAUDE"] = ('claude -n "$KIT_ROLE" --model claude-opus-5 --settings adapters/claude-code/settings.json '
                          '--mcp-config .mcp.json --strict-mcp-config --allowed-tools Read "Bash(bin/tick.sh)" '
                          '"Bash(bin/tick.sh:*)" "Bash(bin/brain.sh:*)" "Bash(bin/restart-self.sh:*)"')
pid, fd = pty.fork()
if pid == 0:
    os.chdir(K); os.execvpe("bash", ["bash", "adapters/claude-code/role-loop.sh", ROLE], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
buf = []; raw = open(LOG, "w"); done = [False]
def pump(sec):
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try: d = os.read(fd, 65536).decode("utf-8", "replace")
            except OSError: done[0] = True; return
            buf.append(d); raw.write(d); raw.flush()
def flat(n=3000): return re.sub(r"\s+", "", ANSI.sub("", "".join(buf))[-n:].lower())
def send(s):
    try: os.write(fd, s.encode())
    except OSError: pass
def claude_pids():
    out = os.popen(f"pgrep -P {pid}").read().split()
    res = []
    for c in out:          # role-loop bash -> subshell -> claude
        res += os.popen(f"pgrep -P {c} -x claude").read().split()
        res += [c] if os.popen(f"ps -o comm= -p {c}").read().strip().endswith("claude") else []
    return sorted(set(int(x) for x in res))
def roster():
    f = glob.glob(os.path.join(K, "sprints/*/roster.md"))
    return [l.strip() for l in open(f[0]) if f"| {ROLE} |" in l] if f else []
def row():
    r = roster(); 
    if not r: return None, None
    c = [x.strip() for x in r[0].split("|")]
    return c[3], c[5]
def reg(p):
    try: return json.load(open(os.path.expanduser(f"~/.claude/sessions/{p}.json"))).get("sessionId")
    except Exception: return None
trusted = []
def wait_for(pred, sec, label):
    end = time.time() + sec
    while time.time() < end and not done[0]:
        pump(2)
        f = flat()
        if "yes,itrustthisfolder" in f and "entertoconfirm" in f and len(trusted) < 3:
            trusted.append(time.time()); print(f"  Vertrauensdialog → Yes (#{len(trusted)})"); send("\x1b[B"); pump(0.8); send("\r"); buf.clear(); continue
        if pred(): return True
    print(f"  ZEITUEBERSCHREITUNG/ENDE: {label}"); return False
t0 = time.time(); T = lambda: int(time.time() - t0)
print(f"role-loop bash PID {pid}")
res = {}
res["start1"] = wait_for(lambda: row()[0] is not None, 180, "erster Start registriert")
sid1, pid1 = row(); res.update(sid1=sid1, pid1=pid1, reg1=reg(pid1))
print(f"[{T()}s] Start 1: roster sid={sid1} pid={pid1} · Registry={res['reg1']} · claude-Kinder={claude_pids()}")
pump(15)
send("Schreibe jetzt mit bin/brain.sh handover \"Neustart-Test\" eine kurze Uebergabe (Rumpf: kein Ticket, Test des Neustarts) und fuehre danach bin/restart-self.sh stop \"Neustart-Test\" aus. Sonst nichts."); pump(1); send("\r")
res["alt_beendet"] = wait_for(lambda: str(pid1) and not os.path.exists(f"/proc/{pid1}") and os.system(f"kill -0 {pid1} 2>/dev/null") != 0, 240, "alter claude-Prozess beendet")
print(f"[{T()}s] alter Prozess {pid1} beendet: {res['alt_beendet']}")
res["neu_registriert"] = wait_for(lambda: row()[1] not in (None, pid1), 240, "neuer Prozess registriert ohne Eingabe")
sid2, pid2 = row(); res.update(sid2=sid2, pid2=pid2, reg2=reg(pid2))
anker = os.path.join(K, ".pid-roles", str(pid2))
res["anker2"] = open(anker).read().strip() if os.path.exists(anker) else None
print(f"[{T()}s] Start 2: roster sid={sid2} pid={pid2} · Registry={res['reg2']} · Anker={res['anker2']} · claude-Kinder={claude_pids()}")
pump(20)
loglines = open(os.path.join(K, ".role-loop", f"{ROLE}.log")).read().splitlines() if os.path.exists(os.path.join(K, ".role-loop", f"{ROLE}.log")) else []
res["starts_im_log"] = sum("starte claude" in l for l in loglines)
res["handover"] = len(glob.glob(os.path.join(K, "memory", ROLE, "handover", "*.md")))
chat = open(glob.glob(os.path.join(K, "sprints/*/chat", f"{ROLE}.md"))[0]).read() if glob.glob(os.path.join(K, "sprints/*/chat", f"{ROLE}.md")) else ""
res["neustart_im_chat"] = "Neustart (stop)" in chat
# Stoppen: Stopp-Datei, dann claude beenden — die Schleife darf nicht erneut starten.
open(os.path.join(K, ".role-loop", f"{ROLE}.stop"), "w").close()
for p in claude_pids(): os.kill(p, signal.SIGTERM)
end = time.time() + 30
while time.time() < end:
    pump(1)
    w, _ = os.waitpid(pid, os.WNOHANG)
    if w: res["schleife_endet_mit_stopp"] = True; break
else:
    res["schleife_endet_mit_stopp"] = False; os.kill(pid, signal.SIGTERM)
loglines = open(os.path.join(K, ".role-loop", f"{ROLE}.log")).read().splitlines()
res["log"] = [l.split(" · ", 1)[1] for l in loglines if " · " in l][-8:]
print("ERGEBNIS", json.dumps(res, ensure_ascii=False))
