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
        text = re.sub(r"^verified:.*?(?=^\w|\n---)", f"verified:\n  - {{by: wiki.sh, at: {now()}}}\n", text, count=1, flags=re.S | re.M)
        rel = os.path.relpath(p, STAGING)
        if rel.startswith(".."):
            die("--promote works only on a file under the staging directory")
        dest = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, "w", encoding="utf-8").write(text)
        os.remove(p)
        print(f"promoted: {dest}")


def cmd_lint(_):
    cs = concepts(ROOT)
    problems = []
    idx = os.path.join(ROOT, "index.md")
    linked = set(re.findall(r"\]\(([^)#]+\.md)", open(idx).read())) if os.path.exists(idx) else set()
    if not os.path.exists(idx):
        problems.append("index.md missing")
    elif len(open(idx).read().split("\n")) > 200:
        problems.append("index.md over 200 lines")
    names = {rel for rel, _, _ in cs}
    today = datetime.datetime.now(datetime.timezone.utc)
    for rel, fm, body in cs:
        if not fm.get("type"):
            problems.append(f"{rel}: no type")
        if rel not in linked:
            problems.append(f"{rel}: orphan (not linked from index.md)")
        for l in re.findall(r"\]\(([^)#]+\.md)", body):
            if os.path.normpath(os.path.join(os.path.dirname(rel), l)) not in names:
                problems.append(f"{rel}: dead link {l}")
        sa = fm.get("stale_after")
        if sa and re.match(r"\d{4}-\d\d-\d\dT", str(sa)) and str(sa) < now():
            problems.append(f"{rel}: stale_after passed ({sa})")
        gen = re.search(r"at:\s*(\d{4}-\d\d-\d\d)", " ".join(as_list(fm.get("generated"))) or str(fm.get("generated", "")))
        if gen and not as_list(fm.get("verified")):
            age = (today.date() - datetime.date.fromisoformat(gen.group(1))).days
            if age > 14:
                problems.append(f"{rel}: unverified for {age} days")
    for l in linked:
        if not os.path.exists(os.path.join(ROOT, l)):
            problems.append(f"index.md: dead link {l}")
    print(f"lint: {len(cs)} concept(s), {len(problems)} problem(s)")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1 if problems else 0)


CMDS = {"seed": cmd_seed, "query": cmd_query, "add": cmd_add, "verify": cmd_verify,
        "lint": cmd_lint, "receipt": cmd_receipt, "gate": cmd_gate}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        die("usage: wiki.sh {seed|query|add|verify|lint|receipt|gate} ...")
    CMDS[sys.argv[1]](sys.argv[2:])
