"""Fine-tune the Laya multilingual checkpoint on rows from wiki_laya_data.py. Run with the Python that has `laya` installed.

  python laya_train.py <work_dir>     reads <work_dir>/laya-data/{train,heldout}.jsonl, writes <work_dir>/laya-ft
MEASURED 2026-11-06: 1 692 rows, 4 epochs, MPS, 772 s. Held-out accuracy 0.525 -> 0.891
(the run itself says the held-out set overlaps the training data; the independent test is laya_eval.py on the golden questions).
"""
import os, sys, time
from huggingface_hub import snapshot_download
from laya import train

d = snapshot_download("convaiinnovations/laya")
md = os.path.join(d, "multilingual") if os.path.isdir(os.path.join(d, "multilingual")) else d
sp = sys.argv[1]
cfg = train.TrainConfig(epochs=4, micro_batch=8, grad_accum=2, loss="soft-ce",
                        eval_data=sp + "/laya-data/heldout.jsonl", log_every=20)
t = time.time()
r = train.finetune(sp + "/laya-data/train.jsonl", md, sp + "/laya-ft", cfg, device="mps")
print("train s %.0f" % (time.time() - t))
print({k: v for k, v in r.items() if not isinstance(v, (list, dict))})
