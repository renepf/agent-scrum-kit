"""A real restart under adapters/claude-code/role-loop.sh.
The role writes its handover and calls bin/restart-self.sh stop itself. What is measured is whether the
loop starts claude again, the wake hook brings the new session into the role, and it registers with a new
PID and a new session id. A clean environment (the equivalent of env -i)."""
import fcntl, glob, json, os, pty, re, select, signal, struct, sys, termios, time
K, LOG = sys.argv[1], sys.argv[2]
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][A-Za-z0-9]|\x1b[=>]|\r")
ROLE = "engineer-a"
env = {k: os.environ[k] for k in ("HOME", "PATH", "USER", "LANG") if k in os.environ}
env["TERM"] = "xterm-256color"
# The command override only adds the model, a strict MCP list and permissions for the three kit scripts,
# so that no permission prompt blocks the test. Everything else is the loop's default command.
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
            trusted.append(time.time()); print(f"  trust dialog → Yes (#{len(trusted)})"); send("\x1b[B"); pump(0.8); send("\r"); buf.clear(); continue
        if pred(): return True
    print(f"  TIMED OUT/ENDED: {label}"); return False
t0 = time.time(); T = lambda: int(time.time() - t0)
print(f"role-loop bash PID {pid}")
res = {}
res["start1"] = wait_for(lambda: row()[0] is not None, 180, "first start registered")
sid1, pid1 = row(); res.update(sid1=sid1, pid1=pid1, reg1=reg(pid1))
print(f"[{T()}s] start 1: roster sid={sid1} pid={pid1} · registry={res['reg1']} · claude children={claude_pids()}")
pump(15)
send("Write a short handover now with bin/brain.sh handover \"restart test\" (body: no ticket, a test of the restart) and then run bin/restart-self.sh stop \"restart test\". Nothing else."); pump(1); send("\r")
res["old_ended"] = wait_for(lambda: str(pid1) and not os.path.exists(f"/proc/{pid1}") and os.system(f"kill -0 {pid1} 2>/dev/null") != 0, 240, "the old claude process ended")
print(f"[{T()}s] old process {pid1} ended: {res['old_ended']}")
res["registered_again"] = wait_for(lambda: row()[1] not in (None, pid1), 240, "a new process registered without input")
sid2, pid2 = row(); res.update(sid2=sid2, pid2=pid2, reg2=reg(pid2))
anchor = os.path.join(K, ".pid-roles", str(pid2))
res["anchor2"] = open(anchor).read().strip() if os.path.exists(anchor) else None
print(f"[{T()}s] start 2: roster sid={sid2} pid={pid2} · registry={res['reg2']} · anchor={res['anchor2']} · claude children={claude_pids()}")
pump(20)
loglines = open(os.path.join(K, ".role-loop", f"{ROLE}.log")).read().splitlines() if os.path.exists(os.path.join(K, ".role-loop", f"{ROLE}.log")) else []
res["starts_in_log"] = sum("starting claude" in l for l in loglines)
res["handover"] = len(glob.glob(os.path.join(K, "memory", ROLE, "handover", "*.md")))
chat = open(glob.glob(os.path.join(K, "sprints/*/chat", f"{ROLE}.md"))[0]).read() if glob.glob(os.path.join(K, "sprints/*/chat", f"{ROLE}.md")) else ""
res["restart_in_chat"] = "Restart (stop)" in chat
# Stopping: the stop file, then end claude — the loop must not start again.
open(os.path.join(K, ".role-loop", f"{ROLE}.stop"), "w").close()
for p in claude_pids(): os.kill(p, signal.SIGTERM)
end = time.time() + 30
while time.time() < end:
    pump(1)
    w, _ = os.waitpid(pid, os.WNOHANG)
    if w: res["loop_ends_on_stop"] = True; break
else:
    res["loop_ends_on_stop"] = False; os.kill(pid, signal.SIGTERM)
loglines = open(os.path.join(K, ".role-loop", f"{ROLE}.log")).read().splitlines()
res["log"] = [l.split(" · ", 1)[1] for l in loglines if " · " in l][-8:]
print("RESULT", json.dumps(res, ensure_ascii=False))
