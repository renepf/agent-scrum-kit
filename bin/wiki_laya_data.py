#!/usr/bin/env python3
"""wiki_laya_data.py - build Laya training rows from the wiki (no model call, no golden question).

  python wiki_laya_data.py <WIKI_ROOT> <out_dir>      writes train.jsonl and heldout.jsonl

Labels come from the concept's frontmatter, not from a person or a model:
  kind     code | requirement | ticket     from the source tag (ios, and -> code; req -> requirement; ops -> ticket)
  side     ios | android | none            from the source tag; requirement and ticket concepts are none
  feature  the first folder under the wiki (auth, sales, parity)
Texts are the verified German descriptions plus section headings. To teach the platform, code texts are wrapped
in a question frame that names the platform for 70 % of the rows (label = the platform) and leaves it out for 30 %
(label = none). The frames are ours (assumption, not measured); the golden questions are never read here.
Split: by file, 15 % of files held out, chosen by a stable hash.
"""
import hashlib, json, os, re, sys

KIND = {"ios": "code", "and": "code", "req": "requirement", "ops": "ticket"}
SIDE = {"ios": "ios", "and": "android", "req": "none", "ops": "none"}
NAME = {"ios": ["iOS", "der iOS-App", "Swift"], "android": ["Android", "der Android-App", "Kotlin"]}
FRAMES = ["Wo wird in {p} {t} geregelt?", "Welche Stelle in {p}: {t}", "Wie macht {p} das: {t}", "{t} ({p})"]
FRAMES0 = ["Wo wird {t} geregelt?", "Welche Stelle: {t}", "Wie funktioniert das: {t}", "{t}"]

Q = {
    "kind": {"type": "choice", "instructions": "Welche Art von Quelle beantwortet die Frage?", "criteria": {
        "code": "Die Frage sucht eine Stelle im Quellcode: wo wird etwas gemacht, welche Datei, welche Funktion, welche Zeile",
        "requirement": "Die Frage sucht eine Anforderung, eine Spezifikation oder eine Regel des Produkts",
        "ticket": "Die Frage sucht ein Ticket, eine Entscheidung, einen Auftrag oder den Projektstand"}},
    "side": {"type": "choice", "instructions": "Welche Plattform nennt die Frage ausdruecklich?", "criteria": {
        "ios": "iOS, Swift, iPhone oder Apple wird genannt",
        "android": "Android, Kotlin, Compose oder Google wird genannt",
        "none": "keine Plattform wird genannt"}},
    "feature": {"type": "choice", "instructions": "Zu welchem Produktthema gehoert der Text?", "criteria": {
        "auth": "Anmeldung, Registrierung, Konto, E-Mail-Bestaetigung, Passwort, Abmelden",
        "sales": "Paywall, Abo, Kauf, Preis, Verkaufsscreen, Zahlung",
        "parity": "Abgleich Android gegen iOS, Parity-Status, Geraeteabnahme"}},
}


def h(s):
    return int(hashlib.sha1(s.encode()).hexdigest(), 16)


def main(root, out):
    os.makedirs(out, exist_ok=True)
    tr, ho = [], []
    for dp, _, fs in os.walk(root):
        for f in sorted(fs):
            if not f.endswith(".md") or f in ("index.md", "log.md"):
                continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root)
            if "/" not in rel:
                continue
            text = open(p, encoding="utf-8").read()
            m = re.search(r"^sources:\n\s+- ([A-Za-z0-9_-]+):", text, re.M)
            if not m or m.group(1) not in KIND:
                continue
            tag, feat = m.group(1), rel.split("/")[0]
            texts = [x.strip() for x in re.findall(r"^\s*Beschreibung: (.+)$", text, re.M)]
            texts += [x.strip() for x in re.findall(r"^- `(.+?)` \(h[1-6]\)", text, re.M)]
            for i, t in enumerate(texts):
                t = t.rstrip(".")
                if len(t.split()) < 3:
                    continue
                for v in range(3 if KIND[tag] == "code" else 1):  # code is the minority class: three frames per text
                    k = rel + str(i) + str(v)
                    side = SIDE[tag]
                    if KIND[tag] == "code" and h(k) % 10 < 7:
                        pl = NAME[side][h(k + "p") % 3]
                        state = FRAMES[h(k + "f") % 4].format(p=pl, t=t[0].lower() + t[1:])
                    else:
                        state = FRAMES0[h(k + "f") % 4].format(t=t[0].lower() + t[1:])
                        side = "none"
                    row = {"state": state, "questions": Q, "expected": {"kind": KIND[tag], "side": side, "feature": feat}}
                    (ho if h(rel) % 100 < 15 else tr).append(row)
    for name, rows in (("train", tr), ("heldout", ho)):
        with open(os.path.join(out, name + ".jsonl"), "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"train {len(tr)} rows, heldout {len(ho)} rows -> {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
