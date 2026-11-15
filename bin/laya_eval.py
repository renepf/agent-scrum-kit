"""Compare base and fine-tuned Laya on the golden questions: source kind, platform, topic (argmax vs expected labels).

  WIKI_GOLDEN=<golden.json> WIKI_LAYA_MODEL=<fine-tuned dir> python laya_eval.py
Expected kind is always code, side comes from the expected source tag, topic from the expected path (sales or auth).
MEASURED 2026-11-06 (17 questions): base kind 17, side 17, feature 14; fine-tuned kind 17, side 16, feature 17.
"""
import json, os, sys
import laya

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wiki_laya_data import Q

G = json.load(open(os.environ["WIKI_GOLDEN"]))
for name, loader in (("base", lambda: laya.load("convaiinnovations/laya", subfolder="multilingual")),
                     ("fine-tuned", lambda: laya.load(os.environ["WIKI_LAYA_MODEL"]))):
    a = loader()
    c, bad = {"kind": 0, "side": 0, "feature": 0}, []
    for g in G:
        e = g["expected"][0]
        exp = {"kind": "code", "side": {"ios": "ios", "and": "android"}[e["side"]],
               "feature": "sales" if "sales" in e["path_suffix"] else "auth"}
        r = a.predict(g["question"], Q)["answers"]
        for k in c:
            ok = r[k]["choice"] == exp[k]
            c[k] += ok
            if not ok:
                bad.append((g["id"][:22], k, r[k]["choice"], round(r[k]["probabilities"][r[k]["choice"]], 2)))
    print(name, {k: f"{v}/{len(G)}" for k, v in c.items()})
    print("  wrong:", bad)
