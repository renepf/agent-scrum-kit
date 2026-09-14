"""Treibt eine interaktive claude-Session ueber ein Pseudo-Terminal durch Start und /clear.

    python3 clear-pty.py <kit-kopie> <bildschirm-log>

Saubere Umgebung wie in einem frischen Terminal: nur HOME, PATH, USER, LANG, TERM, KIT_ROLE.
Eine aus einer laufenden claude-Session vererbte Umgebung (CLAUDE_CODE_CHILD_SESSION, CLAUDE_PID,
Messaging-Socket) macht die gestartete Session zur Kind-Session — sie schrieb dann weder Registry
noch Transkript am ueblichen Ort (gemessen 2026-09-14).

Letzte Zeile: ERGEBNIS <json>.
"""
import fcntl, glob, json, os, pty, re, select, signal, struct, sys, termios, time
K, LOG = sys.argv[1], sys.argv[2]
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][A-Za-z0-9]|\x1b[=>]|\r")
# Saubere Umgebung wie in einem frischen Terminal: keine CLAUDE*-Variablen der aufrufenden Session.
env = {k: os.environ[k] for k in ("HOME", "PATH", "USER", "LANG") if k in os.environ}
env.update(KIT_ROLE="engineer-a", TERM="xterm-256color")
print("Umgebung:", sorted(env))
cmd = ["claude", "-n", "clear-probe", "--model", "claude-opus-5", "--settings", "adapters/claude-code/settings.json",
       "--mcp-config", ".mcp.json", "--strict-mcp-config", "--allowed-tools", "Read", "Bash(bin/tick.sh)", "Bash(bin/tick.sh:*)"]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(K); os.execvpe(cmd[0], cmd, env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
os.kill(pid, signal.SIGWINCH)
raw = open(LOG + ".raw", "w")
buf = []; exited = [None]
def alive():
    if exited[0] is not None: return False
    w, st = os.waitpid(pid, os.WNOHANG)
    if w: exited[0] = st; return False
    return True
def pump(sec):
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try: d = os.read(fd, 65536).decode("utf-8", "replace")
            except OSError: return
            buf.append(d); raw.write(d); raw.flush()
        if not alive(): return
def screen(n=3000): return ANSI.sub("", "".join(buf))[-n:]
def send(s):
    if alive(): os.write(fd, s.encode())
def reg():
    # Erst die Datei der eigenen PID; sonst jede Registry-Datei, deren pid-Feld oder cwd passt.
    try: return json.load(open(os.path.expanduser(f"~/.claude/sessions/{pid}.json"))).get("sessionId")
    except Exception: pass
    for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try: d = json.load(open(f))
        except Exception: continue
        if d.get("pid") == pid or d.get("cwd") == K:
            return d.get("sessionId")
    return None
def reg_dump():
    out = []
    for f in sorted(glob.glob(os.path.expanduser("~/.claude/sessions/*.json")), key=os.path.getmtime)[-6:]:
        try: d = json.load(open(f)); out.append((os.path.basename(f), d.get("pid"), (d.get("sessionId") or "")[:8], d.get("cwd", "")[-30:], d.get("name")))
        except Exception: pass
    return out
def roster():
    f = glob.glob(os.path.join(K, "sprints/*/roster.md"))
    return [l.strip() for l in open(f[0]) if "| engineer-a |" in l] if f else []
seen_dialogs = set()
def wait_for(pred, sec, label):
    end = time.time() + sec
    while time.time() < end and alive():
        pump(2)
        low = re.sub(r"\s+", " ", screen(2500).lower())
        flat = re.sub(r"\s+", "", screen(2500).lower())
        if "yes,itrustthisfolder" in flat and "trust" not in seen_dialogs:
            seen_dialogs.add("trust"); print("  Vertrauensdialog: Pfeil runter auf 'Yes, I trust', Enter"); send("\x1b[B"); pump(0.8); send("\r"); continue
        for key, trig in (("mcp", "newmcpserver"), ("hooks", "hooksconfig")):
            if trig in flat and key not in seen_dialogs and "entertoconfirm" in flat:
                seen_dialogs.add(key); print(f"  Dialog '{key}' → Enter"); send("\r"); break
        if pred(): return True
    if not alive(): print(f"  PROZESS BEENDET waehrend: {label} · status={exited[0]}")
    else: print(f"  ZEITUEBERSCHREITUNG: {label}")
    return False
t0 = time.time(); print(f"claude-PID {pid}")
ok1 = wait_for(lambda: any("| engineer-a |" in r for r in roster()), 180, "Start → Registrierung ohne Eingabe")
pump(6)
print("  Registry-Dateien (neueste 6):", reg_dump())
sid_roster1 = (roster() or ["|||"])[0].split("|")[3].strip()
sid1 = reg() or sid_roster1; print(f"[{int(time.time()-t0)}s] Start: Registry={sid1} · roster={roster()} · Anker={open(os.path.join(K,'.pid-roles',str(pid))).read().strip() if os.path.exists(os.path.join(K,'.pid-roles',str(pid))) else None}")
res = {"start_ok": ok1, "sid1": sid1}
if ok1:
    pump(20)
    send("/clear"); pump(1.5); send("\r")
    ok2 = wait_for(lambda: reg() not in (None, sid1), 60, "/clear → neue Registry-ID")
    sid2 = reg(); print(f"[{int(time.time()-t0)}s] /clear: Registry={sid2} · Registry-Dateien: {reg_dump()}")
    ok3 = wait_for(lambda: any(("| engineer-a |" in r) and (sid1 not in r) for r in roster()), 180, "/clear → Neuregistrierung ohne Eingabe")
    if not sid2 or sid2 == sid1:
        sid2 = (roster() or ["|||"])[0].split("|")[3].strip()
    print(f"[{int(time.time()-t0)}s] roster={roster()}")
    tick = anchor = 0
    for f in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid2}.jsonl")):
        for line in open(f):
            if "bin/tick.sh" in line and '"tool_use"' in line: tick += 1
            if "ROLLENANKER" in line: anchor += 1
    res.update(clear_neue_id=ok2, clear_neu_registriert=ok3, sid2=sid2, tick_aufrufe_nach_clear=tick, rollenanker_zeilen=anchor)
open(LOG, "w").write(screen(30000))
send("/exit"); pump(1); send("\r"); pump(3)
if "exitandstoptasks" in re.sub(r"\s+", "", screen(1500).lower()):
    print("  Exit-Dialog 'Background work is running' → 1. Exit and stop tasks"); send("1"); pump(0.5); send("\r"); pump(3)
if alive():
    os.kill(pid, signal.SIGTERM); pump(2)
for k in ("sid1", "sid2"):
    s = res.get(k)
    fs = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{s}.jsonl")) if s else []
    res[k + "_transkript"] = bool(fs)
print("ERGEBNIS", json.dumps(res))
