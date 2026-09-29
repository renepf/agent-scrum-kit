"""wiki_scan.py - deterministic pass of the first fill (no model). Used by `wiki.sh scan <scope.json>`.

Scope file: {"feature": "auth", "title": "...", "readme": "<source of the feature quote>",
             "sources": [{"tag": "ios", "commit": "de5b082", "globs": ["AWAVE/.../Auth/*.swift"], "kind": "swift|kotlin|md"}]}
Each matched file becomes one concept with a symbol table: name, kind, line range, and a verbatim quote of the
declaration line. The quote is what `wiki.sh verify` checks. The line RANGE comes from brace matching and is a
heuristic; only the declaration line is proven by the quote.
"""
import fnmatch, json, os, re, subprocess, sys

KT = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|internal|protected|data|sealed|enum|open|abstract|"
                r"suspend|override|inline|tailrec|operator|fun\s+interface|value|annotation)\s+)*"
                r"(class|object|interface|fun|typealias)\s+(?:<[^>]*>\s*)?(?:[\w.<>?, ]+\.)?(\w+)")
SW = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|static|override|"
                r"mutating|nonisolated|convenience|indirect)\s+)*(class|struct|enum|protocol|extension|func|actor|init)\b\s*([\w.]*)")
MD = re.compile(r"^(#{1,6})\s+(.+?)\s*$")


def git(repo, *a):
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"git {' '.join(a)} failed in {repo}: {r.stderr.strip()[:200]}")
    return r.stdout


def strip_code(line):
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    return re.sub(r"//.*$", "", line)


def span(lines, i):
    depth = paren = 0
    seen = False
    for j in range(i, min(len(lines), i + 4000)):
        t = strip_code(lines[j])
        for ch in t:
            if ch == "{":
                depth += 1; seen = True
            elif ch == "}":
                depth -= 1
            elif ch == "(":
                paren += 1
            elif ch == ")":
                paren -= 1
        if seen and depth <= 0:
            return j
        if not seen and paren <= 0 and j >= i:
            nxt = strip_code(lines[j + 1]).strip() if j + 1 < len(lines) else ""
            if not t.rstrip().endswith(("=", ",", "(", "->", "&&", "||", "+", ":")) and not nxt.startswith("{"):
                return j
    return i


def symbols(kind, lines):
    out, fence = [], False
    if kind == "md":
        heads = []
        for i, l in enumerate(lines):
            if l.lstrip().startswith("```"):
                fence = not fence
            m = None if fence else MD.match(l)
            if m:
                heads.append((i, m.group(2), f"h{len(m.group(1))}"))
        for k, (i, name, kd) in enumerate(heads):
            end = heads[k + 1][0] - 1 if k + 1 < len(heads) else len(lines) - 1
            while end > i and not lines[end].strip():
                end -= 1
            out.append((name, kd, i + 1, end + 1))
        return out
    rx = KT if kind == "kotlin" else SW
    for i, l in enumerate(lines):
        m = rx.match(l)
        if m and not l.lstrip().startswith(("//", "*", "/*")):
            name = m.group(2) or m.group(1)
            out.append((name, m.group(1), i + 1, span(lines, i) + 1))
    return out


def slug(path):
    parts = re.sub(r"\.md$", "", path).split("/")[-2:]
    return re.sub(r"[^A-Za-z0-9._-]+", "-", "__".join(parts)).strip("-")


def ctype(kind, path):
    if kind == "md":
        return "requirement"
    return "screen" if re.search(r"(View|Screen|Card|Drawer|Section|Strip|Bullet|Modal|Effect)\.(kt|swift)$", path) else "service"


def run(scope_path, repos, root, now):
    sc = json.load(open(scope_path, encoding="utf-8"))
    feat = sc["feature"]
    outdir = os.path.join(root, feat)
    os.makedirs(outdir, exist_ok=True)
    made, links = [], []
    for src in sc["sources"]:
        repo = repos.get(src["tag"]) or raise_(f"unknown repo tag {src['tag']}")
        sha = src["commit"]
        files = git(repo, "ls-tree", "-r", "--name-only", sha).split("\n")
        hit = sorted({f for f in files if f and any(fnmatch.fnmatch(f, g) for g in src["globs"])})
        for f in hit:
            lines = git(repo, "show", f"{sha}:{f}").split("\n")
            if lines and lines[-1] == "":
                lines.pop()
            n = len(lines)
            ref = f"{src['tag']}:{f}:1-{n}@{sha}"
            name = f"{src['tag']}-{slug(f)}.md"
            body = [f"# {os.path.basename(f)} ({src['tag']})", "", f"Feature: [{sc['title']}](../{feat}.md)", "",
                    f"Quelle: `{ref}`, {n} Zeilen. Symboltabelle deterministisch erzeugt; die Zeilenbereiche stammen aus Klammerzaehlung, belegt ist nur die Deklarationszeile.", "",
                    "## Symbole", ""]
            for sname, kd, a, b in symbols(src["kind"], lines):
                q = lines[a - 1].strip()
                body += [f"- `{sname}` ({kd}) Zeilen {a}-{b}", f"  > [{src['tag']}:{f}:{a}-{a}@{sha}] {q}"]
            fm = ["---", f"type: {ctype(src['kind'], f)}", f"title: {os.path.basename(f)} ({src['tag']})",
                  f"description: Quelldatei {f}, {n} Zeilen, Stand {sha}. Typ aus dem Dateinamen abgeleitet.",
                  "tags:", f"  - {feat}", f"  - {src['tag']}",
                  "sources:", f"  - {ref}", "status: draft",
                  f"generated: {{by: wiki.sh scan, at: {now}}}", "verified: []", "---"]
            open(os.path.join(outdir, name), "w", encoding="utf-8").write("\n".join(fm + [""] + body) + "\n")
            made.append((src["tag"], name, f))
    tag, sha = sc["readme"]["tag"], sc["readme"]["commit"]
    rp = sc["readme"]["path"]
    first = git(repos[tag], "show", f"{sha}:{rp}").split("\n")[0].strip()
    lines = ["---", "type: feature", f"title: {sc['title']}", f"description: Feature-Einstieg {sc['title']}: Dateien je Seite (iOS, Android, Anforderungen, Tickets, Parity).",
             "tags:", f"  - {feat}", "sources:", f"  - {tag}:{rp}:1-1@{sha}", "parity_status: UNGEPRUEFT",
             "status: draft", f"generated: {{by: wiki.sh scan, at: {now}}}", "verified: []", "---", "",
             f"# {sc['title']}", "", f"> [{tag}:{rp}:1-1@{sha}] {first}", ""]
    for t in sorted({m[0] for m in made}):
        lines += [f"## {t}", ""] + [f"- [{f}]({feat}/{nm})" for tg, nm, f in made if tg == t] + [""]
    open(os.path.join(root, f"{feat}.md"), "w", encoding="utf-8").write("\n".join(lines))
    print(f"scan {feat}: {len(made)} concept(s) + {feat}.md")
    return made


def raise_(msg):
    raise SystemExit(msg)
