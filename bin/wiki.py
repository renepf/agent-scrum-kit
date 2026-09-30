#!/usr/bin/env python3
"""wiki.py - implementation behind bin/wiki.sh. See protocols/LIBRARIAN.md."""
import datetime, os, re, subprocess, sys

ROOT = os.path.abspath(os.environ.get("WIKI_ROOT", "wiki"))
STAGING = os.path.abspath(os.environ.get("WIKI_STAGING", os.path.join(ROOT, "..", "wiki-staging")))
RECEIPTS = os.environ.get("WIKI_RECEIPT_DIR", os.path.join(os.environ.get("TMPDIR", "/tmp"), "wiki-receipts"))
REPOS = dict(p.split("=", 1) for p in os.environ.get("WIKI_REPOS", "").split(",") if "=" in p)
RESERVED = ("index.md", "log.md")
SRC = re.compile(r"^([A-Za-z0-9_-]+):(.+):(\d+)-(\d+)@([0-9a-f]{7,40})$")
QUOTE = re.compile(r"^> \[([^\]]+)\] (.+)$")


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def parse(text):
    """Frontmatter subset: scalars, [] and '  - item' lists (item may be '{by: x, at: y}')."""
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    if not m:
        return None, text
    fm, key = {}, None
    for line in m.group(1).split("\n"):
        item = re.match(r"^\s+-\s+(.*)$", line)
        kv = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if item and key:
            fm[key].append(item.group(1).strip().strip('"'))
        elif kv:
            key, val = kv.group(1), kv.group(2).strip()
            fm[key] = [] if val in ("", "[]") else val.strip('"')
            if val == "":
                fm[key] = []
    return fm, m.group(2)


def concepts(base):
    out = []
    for dp, _, fs in os.walk(base):
        for f in sorted(fs):
            if f.endswith(".md") and f not in RESERVED:
                p = os.path.join(dp, f)
                fm, body = parse(open(p, encoding="utf-8").read())
                if fm is not None:
                    out.append((os.path.relpath(p, base), fm, body))
    return sorted(out)


def as_list(v):
    return v if isinstance(v, list) else ([v] if v else [])


def cmd_seed(_):
    cs = concepts(ROOT)
    if not cs:
        print("wiki: empty (no concepts). Ask the librarian: wiki.sh add")
        return
    by = {}
    for _, fm, _ in cs:
        t = by.setdefault(fm.get("type", "?"), [0, 0])
        t[0] += 1
        t[1] += 1 if as_list(fm.get("verified")) else 0
    print("wiki: shared project knowledge. Ask before you edit source: wiki.sh query \"<question>\"")
    print(f"concepts: {len(cs)}; index: wiki/index.md")
    for t in sorted(by):
        print(f"- {t}: {by[t][0]} ({by[t][1]} verified, {by[t][0] - by[t][1]} UNGEPRUEFT)")
    print("An empty verified list means UNGEPRUEFT: say so when you use the fact.")


def cmd_query(a):
    if not a:
        die("usage: wiki.sh query \"<question>\"")
    q = " ".join(a).lower()
    terms = {w for w in re.findall(r"[\w]{3,}", q)}
    scored = []
    for rel, fm, body in concepts(ROOT):
        head = " ".join([rel, fm.get("title", ""), fm.get("description", "")] + as_list(fm.get("tags"))).lower()
        text = body.lower()
        s = sum(3 * head.count(t) + text.count(t) for t in terms)
        if s:
            scored.append((-s, rel, fm, body))
    scored.sort()
    sid = os.environ.get("WIKI_SESSION_ID") or os.environ.get("KIT_SESSION_ID")
    if sid:
        cmd_receipt([sid])
    if not scored:
        print("no concept matches. UNKNOWN - not in the wiki; ask the librarian: wiki.sh add")
        return
    for s, rel, fm, body in scored[:5]:
        v = as_list(fm.get("verified"))
        print(f"concept: {rel}  [{fm.get('type', '?')}, {fm.get('status', '?')}, "
              f"{'verified' if v else 'UNGEPRUEFT (verified list empty)'}]")
        print(f"  title: {fm.get('title', '')}")
        for k in ("sources", "android_sources"):
            for src in as_list(fm.get(k)):
                print(f"  {k}: {src}")
        hit = next((l.strip() for l in body.split("\n") if any(t in l.lower() for t in terms)), "")
        if hit:
            print(f"  match: {hit[:200]}")


def cmd_receipt(a):
    if not a:
        die("usage: wiki.sh receipt <session_id>")
    os.makedirs(RECEIPTS, exist_ok=True)
    open(os.path.join(RECEIPTS, re.sub(r"[^\w.-]", "_", a[0])), "w").write(now() + "\n")


def cmd_gate(a):
    if not a:
        die("usage: wiki.sh gate <session_id>")
    if os.path.exists(os.path.join(RECEIPTS, re.sub(r"[^\w.-]", "_", a[0]))):
        return
    die('DENIED: no wiki query in this session yet. Run: wiki.sh query "<question>" (then retry).', 2)


def cmd_add(a):
    if len(a) < 3:
        die("usage: wiki.sh add <type> <title> <text...>   (a request; the librarian applies it)")
    os.makedirs(os.path.join(STAGING, "requests"), exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", a[1].lower()).strip("-")[:60] or "request"
    p = os.path.join(STAGING, "requests", f"{slug}.md")
    if os.path.exists(p):
        die(f"request exists: {p}")
    open(p, "w", encoding="utf-8").write(
        f"---\ntype: {a[0]}\ntitle: {a[1]}\nstatus: draft\nverified: []\n---\n{' '.join(a[2:])}\n")
    print(f"queued: {p}")


def git_lines(src):
    m = SRC.match(src)
    if not m:
        return None, f"bad source '{src}' (want tag:path:a-b@commit)"
    tag, path, a, b, sha = m.groups()
    if tag not in REPOS:
        return None, f"unknown repo tag '{tag}' (set WIKI_REPOS)"
    r = subprocess.run(["git", "-C", REPOS[tag], "show", f"{sha}:{path}"], capture_output=True, text=True)
    if r.returncode:
        return None, f"cannot read {tag}:{path}@{sha}"
    ls = r.stdout.split("\n")
    a, b = int(a), int(b)
    if a < 1 or b < a or b > len(ls):
        return None, f"line range {a}-{b} outside {tag}:{path}@{sha} ({len(ls)} lines)"
    return "\n".join(ls[a - 1:b]), None


def cmd_verify(a):
    promote = "--promote" in a
    a = [x for x in a if x != "--promote"]
    if len(a) != 1:
        die("usage: wiki.sh verify <file> [--promote]")
    p = os.path.abspath(a[0])
    fm, body = parse(open(p, encoding="utf-8").read())
    if fm is None:
        die(f"REJECT {a[0]}: no frontmatter")
    bad, ok = [], 0
    for src in as_list(fm.get("sources")) + as_list(fm.get("android_sources")):
        txt, err = git_lines(src)
        if err:
            bad.append(err)
    for line in body.split("\n"):
        m = QUOTE.match(line)
        if not m:
            continue
        txt, err = git_lines(m.group(1))
        if err:
            bad.append(err)
        elif re.sub(r"\s+", " ", m.group(2)).strip() not in re.sub(r"\s+", " ", txt):
            bad.append(f"quote not found in {m.group(1)}: {m.group(2)[:80]}")
        else:
            ok += 1
    if not ok and not bad:
        bad.append("no quoted claim (> [tag:path:a-b@commit] verbatim text)")
    if bad:
        print(f"REJECT {a[0]}: {len(bad)} problem(s), {ok} quote(s) ok")
        for b in bad:
            print(f"  - {b}")
        sys.exit(1)
    print(f"VERIFIED {a[0]}: {ok} quote(s) found verbatim at the pinned commit")
    if promote:
        text = open(p, encoding="utf-8").read()
        stamp = f"verified:\n  - {{by: wiki.sh, at: {now()}}}\n"
        text = re.sub(r"^verified:[^\n]*\n(?:[ \t]+-[^\n]*\n)*", stamp, text, count=1, flags=re.M)
        if not os.path.relpath(p, STAGING).startswith(".."):
            dest = os.path.join(ROOT, os.path.relpath(p, STAGING))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            open(dest, "w", encoding="utf-8").write(text)
            os.remove(p)
            print(f"promoted: {dest}")
        elif not os.path.relpath(p, ROOT).startswith(".."):
            open(p, "w", encoding="utf-8").write(text)
            print(f"verified in place: {p}")
        else:
            die("--promote works only on a file under staging or the wiki")


def cmd_lint(_):
    cs = concepts(ROOT)
    problems = []
    idx = os.path.join(ROOT, "index.md")
    names = {rel for rel, _, _ in cs}
    graph = {rel: {os.path.normpath(os.path.join(os.path.dirname(rel), l))
                   for l in re.findall(r"\]\(([^)#\s]+\.md)", body)} for rel, _, body in cs}
    reach, todo = set(), []
    if not os.path.exists(idx):
        problems.append("index.md missing")
    else:
        text = open(idx, encoding="utf-8").read()
        if len(text.split("\n")) > 200:
            problems.append("index.md over 200 lines")
        todo = [os.path.normpath(l) for l in re.findall(r"\]\(([^)#\s]+\.md)", text)]
        for l in todo:
            if l not in names and not os.path.exists(os.path.join(ROOT, l)):
                problems.append(f"index.md: dead link {l}")
    while todo:
        c = todo.pop()
        if c in reach or c not in graph:
            continue
        reach.add(c)
        todo.extend(graph[c])
    today = datetime.datetime.now(datetime.timezone.utc)
    for rel, fm, body in cs:
        if not fm.get("type"):
            problems.append(f"{rel}: no type")
        if rel not in reach:
            problems.append(f"{rel}: orphan (not reachable from index.md)")
        for l in graph[rel]:
            if l not in names:
                problems.append(f"{rel}: dead link {l}")
        sa = fm.get("stale_after")
        if sa and re.match(r"\d{4}-\d\d-\d\dT", str(sa)) and str(sa) < now():
            problems.append(f"{rel}: stale_after passed ({sa})")
        gen = re.search(r"at:\s*(\d{4}-\d\d-\d\d)", " ".join(as_list(fm.get("generated"))) or str(fm.get("generated", "")))
        if gen and not as_list(fm.get("verified")):
            age = (today.date() - datetime.date.fromisoformat(gen.group(1))).days
            if age > 14:
                problems.append(f"{rel}: unverified for {age} days")
    print(f"lint: {len(cs)} concept(s), {len(problems)} problem(s)")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1 if problems else 0)


def cmd_scan(a):
    if not a:
        die("usage: wiki.sh scan <scope.json>   (deterministic first-fill pass, writes <WIKI_ROOT>/<feature>.md and <feature>/*)")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import wiki_scan
    wiki_scan.run(a[0], REPOS, ROOT, now())


SYM = re.compile(r"^- `(.+?)` \((\w+)\) Zeilen (\d+)-(\d+)\s*$")


def symbols_of(body):
    """(name, kind, a, b, description) for every symbol block of a scanned concept."""
    out, lines = [], body.split("\n")
    for i, l in enumerate(lines):
        m = SYM.match(l)
        if m:
            desc = ""
            for nxt in lines[i + 1:i + 4]:
                if nxt.startswith("  Beschreibung: "):
                    desc = nxt[len("  Beschreibung: "):]
            out.append((m.group(1), m.group(2), int(m.group(3)), int(m.group(4)), desc))
    return out


def src_of(fm):
    m = SRC.match(as_list(fm.get("sources"))[0]) if as_list(fm.get("sources")) else None
    return m.groups() if m else None


def render_cite(tag, path, a, b, sha):
    return f"{tag}:{path}:{a}-{b}@{sha}"


def cmd_ask(a):
    if not a:
        die('usage: wiki.sh ask "<question>"   (local model picks candidates; the script renders file:lines)')
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import wiki_llm
    q = " ".join(a)
    files = [(rel, fm, body) for rel, fm, body in concepts(ROOT) if src_of(fm) and fm.get("type") != "feature"]
    lines = [f"{i}. {rel} | {fm.get('title','')} | {fm.get('description','')}" for i, (rel, fm, _) in enumerate(files)]
    system = "You route questions to source files. Answer only with a line `IDS: n,n,n` (at most 3 ids from the list). No other text."
    fid = wiki_llm.pick_ids(system, f"Question: {q}\n\nFiles:\n" + "\n".join(lines), set(range(len(files))), 3)
    cands = []
    for i in fid:
        rel, fm, body = files[i]
        tag, path, _, _, sha = src_of(fm)
        for name, kind, x, y, desc in symbols_of(body):
            cands.append((rel, tag, path, sha, name, kind, x, y, desc))
    if not cands:
        print("UNKNOWN - no matching file in the wiki")
        return
    cl = [f"{i}. {c[2].split('/')[-1]} | {c[5]} {c[4]} | {c[8]}" for i, c in enumerate(cands)]
    system = "You pick the code location that answers the question. Answer only with a line `IDS: n` (best id first, at most 2). No other text."
    sid = wiki_llm.pick_ids(system, f"Question: {q}\n\nLocations:\n" + "\n".join(cl), set(range(len(cands))), 2)
    if not sid:
        print("UNKNOWN - the model named no location")
        return
    for i in sid:
        rel, tag, path, sha, name, kind, x, y, desc = cands[i]
        print(f"answer: {render_cite(tag, path, x, y, sha)}  ({kind} {name}; concept {rel}; UNGEPRUEFT unless verified)")


def cmd_describe(a):
    if len(a) != 1:
        die("usage: wiki.sh describe <concept-file in the wiki>   (writes the proposal to staging; verify --promote promotes)")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import wiki_llm
    p = os.path.abspath(a[0])
    text = open(p, encoding="utf-8").read()
    fm, body = parse(text)
    ref = src_of(fm)
    if not ref:
        die("no source in frontmatter")
    tag, path, _, _, sha = ref
    r = subprocess.run(["git", "-C", REPOS[tag], "show", f"{sha}:{path}"], capture_output=True, text=True)
    if r.returncode:
        die(f"cannot read source {tag}:{path}@{sha}")
    src = r.stdout.split("\n")
    if src and src[-1] == "":
        src.pop()
    syms = symbols_of(body)
    numbered = "\n".join(f"{i + 1}: {l}" for i, l in enumerate(src))
    system = ("You document source files for a wiki. For the file summary use id 0 and for each listed symbol its id. "
              "One line per id, exactly `ID¦description¦quote` (the separator is the character ¦). The description is ONE German sentence in your own words: say what the code "
              "does for the user or the app, and use the domain words a colleague would search for (for example Bestaetigungsmail, Abmelden, "
              "Anzeigename, Paywall), not only the function name. Never copy the quote into the description. The quote is one single line "
              "copied character by character from that symbol's lines, choose the most telling line, never join two lines and never include the line number. Example line: `12¦Prueft beim Start, ob ein Nutzer angemeldet ist, und zeigt sonst den Anmeldedialog.¦guard let user = session.user else {` "
              "Answer one line for EVERY requested id. No other text.")
    items = [(0, "file summary", 1, len(src))] + [(i, n, x, y) for i, (n, k, x, y, _) in enumerate(syms, 1)]
    kept, rejected, notes, rejlines = 0, 0, {}, []

    def ask_ids(chunk):
        nonlocal kept, rejected
        listing = "\n".join(f"{i}: {n} (lines {x}-{y})" for i, n, x, y in chunk)
        out = wiki_llm.chat(system, f"File {path}\n\nSource:\n{numbered}\n\nDocument exactly these ids:\n{listing}", 2500)
        want = {i for i, _, _, _ in chunk}
        for line in out.split("\n"):
            m = re.match(r"^\s*(\d+)\s*¦(.+?)¦(.+)$", line)
            if not m or int(m.group(1)) not in want or int(m.group(1)) in notes:
                continue
            i, desc, quote = int(m.group(1)), m.group(2).strip(), m.group(3).strip().strip("`")
            a1, b1 = (1, len(src)) if i == 0 else (syms[i - 1][2], syms[i - 1][3])
            bad = len(desc.split()) < 3 or (i and desc.lower() == syms[i - 1][0].lower())
            if not bad and wiki_llm.norm(quote) and wiki_llm.norm(quote) in wiki_llm.norm("\n".join(src[a1 - 1:b1])):
                notes[i] = (desc, quote, a1, b1)
                kept += 1
            else:
                rejected += 1
                rejlines.append(line)

    size = int(os.environ.get("WIKI_DESCRIBE_CHUNK", "10"))
    for start in range(0, len(items), size):
        ask_ids(items[start:start + size])
    missing = [it for it in items if it[0] not in notes]
    for start in range(0, len(missing), size):  # one retry for what the model skipped or got wrong
        ask_ids(missing[start:start + size])
    rejected_final = len(items) - len(notes)
    new, i = [], 0
    for l in body.split("\n"):
        new.append(l)
        m = SYM.match(l)
        if m:
            i += 1
        # description goes right under the declaration quote of its symbol
        if m is None and l.startswith("  > [") and i in notes and not any(x.startswith("  Beschreibung:") for x in new[-3:]):
            new.append(f"  Beschreibung: {notes[i][0]}")
            new.append(f"  > [{tag}:{path}:{notes[i][2]}-{notes[i][3]}@{sha}] {notes[i][1]}")
    ftext = text
    if 0 in notes:
        ftext = re.sub(r"^description:.*$", "description: " + notes[0][0], ftext, count=1, flags=re.M)
        new.insert(new.index("## Symbole") if "## Symbole" in new else 0, f"Beschreibung: {notes[0][0]}\n> [{tag}:{path}:1-{len(src)}@{sha}] {notes[0][1]}\n")
    head = re.match(r"^---\n.*?\n---\n", ftext, re.S).group(0)
    rel = os.path.relpath(p, ROOT)
    dest = os.path.join(STAGING, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, "w", encoding="utf-8").write(head + "\n".join(new))
    if rejlines:
        open(dest + ".rejected.txt", "w", encoding="utf-8").write("\n".join(rejlines) + "\n")
    print(f"describe {rel}: kept {len(notes)}, rejected {rejected_final} of {len(items)} (no valid description with a quote found in the symbol's lines) -> {dest}")


def cmd_golden(a):
    if not a:
        die("usage: wiki.sh golden <golden.json>")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import wiki_golden
    wiki_golden.run(a[0], os.path.join(os.path.dirname(os.path.abspath(__file__)), "wiki.sh"))


def log_add(line):
    p = os.path.join(ROOT, "log.md")
    text = open(p, encoding="utf-8").read() if os.path.exists(p) else "---\ntype: log\ntitle: Wiki-Log\n---\n# Log (neueste zuerst)\n"
    head = "## " + datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    if head not in text:
        text = re.sub(r"(# Log[^\n]*\n)", lambda m: m.group(1) + "\n" + head + "\n", text, count=1)
    m = re.search(re.escape(head) + r"\n(.*?)(?=\n## |\Z)", text, re.S)
    text = text[:m.end()].rstrip("\n") + "\n" + line + "\n" + text[m.end():].lstrip("\n") if m else text + "\n" + line + "\n"
    open(p, "w", encoding="utf-8").write(text)


def cmd_fill(a):
    """describe -> verify --promote for every file concept not yet in log.md; stop file between batches."""
    scope = a[0] if a else ""
    batch = int(os.environ.get("WIKI_FILL_BATCH", "15"))
    stop = os.path.join(ROOT, "..", ".wiki-stop")
    log = open(os.path.join(ROOT, "log.md"), encoding="utf-8").read() if os.path.exists(os.path.join(ROOT, "log.md")) else ""
    todo = [rel for rel, fm, _ in concepts(ROOT)
            if src_of(fm) and fm.get("type") != "feature" and rel.startswith(scope) and f"fill {rel}:" not in log]
    print(f"fill: {len(todo)} concept(s) to do (batch {batch})")
    done = 0
    for k, rel in enumerate(todo):
        if k % batch == 0 and os.path.exists(stop):
            print(f"STOP: {os.path.normpath(stop)} exists; {done} done, {len(todo) - done} left. Resume with the same command.")
            return
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            cmd_describe([os.path.join(ROOT, rel)])
        d = buf.getvalue().strip()
        m = re.search(r"kept (\d+), rejected (\d+) of (\d+)", d)
        staged = os.path.join(STAGING, rel)
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                cmd_verify([staged, "--promote"])
            state = "verified, promoted"
        except SystemExit:
            state = "verify REJECTED, stays in staging"
        line = f"- fill {rel}: kept {m.group(1)}, rejected {m.group(2)} of {m.group(3)}; {state}" if m else f"- fill {rel}: describe gave no count; {state}"
        log_add(line)
        print(line, flush=True)
        done += 1
    print(f"fill: {done} done")


CMDS = {"fill": cmd_fill, "golden": cmd_golden, "describe": cmd_describe, "ask": cmd_ask, "scan": cmd_scan, "seed": cmd_seed, "query": cmd_query, "add": cmd_add, "verify": cmd_verify,
        "lint": cmd_lint, "receipt": cmd_receipt, "gate": cmd_gate}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        die("usage: wiki.sh {seed|query|add|verify|lint|scan|describe|fill|ask|golden|receipt|gate} ...")
    CMDS[sys.argv[1]](sys.argv[2:])
