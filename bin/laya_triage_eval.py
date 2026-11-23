"""Base vs fine-tuned Laya on triage heldout rows: kind, side, feature, each with the row's own question block.

  python laya_triage_eval.py <heldout.jsonl> <ft_dir> [out.json]
Per axis: accuracy, per-class precision/recall/F1, macro-F1, always-majority baseline, confusion matrix; parity separately; median ms per predict.
"""
import collections, json, statistics, sys, time
import laya

AX = ("kind", "side", "feature")
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]


def run(agent):
    pred, ms = [], []
    for r in rows:
        t = time.perf_counter()
        a = agent.predict(r["state"], r["questions"])["answers"]
        ms.append((time.perf_counter() - t) * 1000)
        pred.append({k: a[k]["choice"] for k in AX})
    return pred, ms


def report(name, pred, ms):
    print("\n=== %s: %d rows, median %.0f ms/predict ===" % (name, len(rows), statistics.median(ms)))
    out = {"median_ms": statistics.median(ms)}
    for ax in AX:
        gold = [r["expected"][ax] for r in rows]
        p = [x[ax] for x in pred]
        cl = sorted(set(gold) | set(p))
        maj, mn = collections.Counter(gold).most_common(1)[0]
        acc = sum(g == q for g, q in zip(gold, p)) / len(gold)
        print("\n%s: accuracy %.3f, always-%s baseline %.3f" % (ax, acc, maj, mn / len(gold)))
        print("  %-12s %5s %5s %5s %5s" % ("class", "prec", "rec", "f1", "n"))
        f1s, per = [], {}
        for c in cl:
            tp = sum(g == c and q == c for g, q in zip(gold, p))
            pp, gg = p.count(c), gold.count(c)
            pr, rc = tp / pp if pp else 0.0, tp / gg if gg else 0.0
            f = 2 * pr * rc / (pr + rc) if pr + rc else 0.0
            f1s.append(f); per[c] = [pr, rc, f, gg]
            print("  %-12s %5.2f %5.2f %5.2f %5d" % (c, pr, rc, f, gg))
        print("  macro-F1 %.3f" % (sum(f1s) / len(f1s)))
        print("  confusion (rows gold, cols predicted: %s)" % " ".join(cl))
        for g in cl:
            print("  %-12s %s" % (g, " ".join("%5d" % sum(a == g and b == c for a, b in zip(gold, p)) for c in cl)))
        out[ax] = {"accuracy": acc, "baseline": mn / len(gold), "macro_f1": sum(f1s) / len(f1s), "per_class": per}
    idx = [i for i, r in enumerate(rows) if r["expected"]["feature"] == "parity"]
    hit = sum(pred[i]["feature"] == "parity" for i in idx)
    fp = sum(x["feature"] == "parity" for i, x in enumerate(pred) if i not in set(idx))
    print("\nparity (feature): %d heldout rows, %d predicted parity correctly, %d false parity on other rows. Too few rows for a conclusion." % (len(idx), hit, fp))
    out["parity"] = {"n": len(idx), "hit": hit, "false_pos": fp}
    return out


res = {}
for name, load in (("base", lambda: laya.load("convaiinnovations/laya", subfolder="multilingual", device="mps")),
                   ("triage-ft", lambda: laya.load(sys.argv[2], device="mps"))):
    a = load()
    a.predict(rows[0]["state"], rows[0]["questions"])  # warm-up, not timed
    res[name] = report(name, *run(a))
    del a
if len(sys.argv) > 3:
    json.dump(res, open(sys.argv[3], "w"), indent=1)
