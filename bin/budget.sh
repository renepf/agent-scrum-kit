#!/usr/bin/env bash
# Watchdog: echten Kontextstand je Session aus den Transkripten lesen, budget.md schreiben.
#
# Wo die Transkripte liegen und wie sie aussehen, weiss nur der Host-Adapter:
#   adapters/<host>/transcript-path.sh <session-id>  druckt Pfade, eine je Zeile.
# Schreibt ein Host keine Transkripte, faellt die Rolle auf die Notbremse zurueck
# (Ruhestand nach KIT_MAX_TICKETS) — das steht dann so in budget.md.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPRINT="$(sprint_dir)"
PROBE="$KIT_ROOT/adapters/$KIT_HOST/transcript-path.sh"

python3 - "$SPRINT" "$KIT_WARN_TOKENS" "$KIT_STOP_TOKENS" "$PROBE" "${KIT_MAX_TICKETS:-5}" <<'PY' | atomic_write "$SPRINT/budget.md"
import json, os, subprocess, sys, datetime

sprint, warn, stop, probe, maxtickets = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]

# roster.md: | zeit | rolle | session-id | host |
rows = []
roster = os.path.join(sprint, "roster.md")
if os.path.exists(roster):
    for line in open(roster, encoding="utf-8"):
        f = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(f) >= 3 and f[0].startswith("20"):
            rows.append((f[1], f[2]))

def transcripts(sid):
    """None = der Host kennt gar keine Transkripte (Adapter fehlt oder ist nicht ausfuehrbar).
    Leere Liste = der Adapter lief, fand aber fuer DIESE Kennung nichts. Zwei verschiedene
    Ursachen, zwei verschiedene Meldungen — keine davon ist eine 0."""
    if not os.access(probe, os.X_OK):
        return None
    try:
        out = subprocess.run([probe, sid], capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    if out.returncode != 0:
        return []
    return [p for p in out.stdout.split("\n") if p.strip() and os.path.exists(p)]

def turn(rec):
    """(context, output) of one transcript record, or None. One shape per host, each measured
    (adapters/<host>/README.md)."""
    msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
    u = msg.get("usage") or rec.get("usage") or {}
    if "input_tokens" in u:      # claude-code: input_tokens excludes the cache
        return (u["input_tokens"] + u.get("cache_read_input_tokens", 0)
                + u.get("cache_creation_input_tokens", 0), u.get("output_tokens", 0))
    if "input" in u:             # pi: input excludes cacheRead and cacheWrite
        return u["input"] + u.get("cacheRead", 0) + u.get("cacheWrite", 0), u.get("output", 0)
    m = rec.get("usageMetadata") or {}
    if "promptTokenCount" in m:  # qwen-code: promptTokenCount already contains the cached tokens
        return m["promptTokenCount"], m.get("candidatesTokenCount", 0)
    return None

def usage_for(sid):
    """Kontextgroesse = groesster Eingabestand EINES Turns. Nicht die Summe ueber Turns."""
    paths = transcripts(sid)
    if paths is None:
        return "NOPROBE"
    if not paths:
        return None
    seen = False
    ctx_max = 0
    out_total = 0
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                t = turn(rec) if isinstance(rec, dict) else None
                if t is None:
                    continue
                seen = True
                ctx_max = max(ctx_max, t[0])
                out_total += t[1]
    return (ctx_max, out_total) if seen else "NOUSAGE"

def num(n):
    return f"{n:,}".replace(",", " ")

print(f"# budget · {os.path.basename(sprint)}")
print()
print("GENERIERT von bin/budget.sh. Nicht von Hand editieren.")
print(f"Stand: {datetime.datetime.now():%Y-%m-%d %H:%M} · Warnung ab {num(warn)} · Stopp ab {num(stop)}")
print()
print("Kontext = groesster Eingabestand EINES Turns (input + cache_read + cache_creation),")
print("nicht die Summe ueber alle Turns.")
print("Per host: qwen-code promptTokenCount (contains the cache), pi input + cacheRead + cacheWrite.")
print()
print("| Rolle | Session-ID | Kontext | Output gesamt | Lage |")
print("|---|---|---|---|---|")

stops = []
for rolle, sid in rows:
    res = usage_for(sid)
    if res == "NOPROBE":
        print(f"| {rolle} | `{sid}` | UNKNOWN | UNKNOWN | Host schreibt keine Transkripte — Notbremse nach {maxtickets} Tickets |")
        continue
    if res == "NOUSAGE":
        print(f"| {rolle} | `{sid}` | UNKNOWN | UNKNOWN | transcript has no usage record this kit knows — not read as 0 |")
        continue
    if res is None:
        print(f"| {rolle} | `{sid}` | UNKNOWN | UNKNOWN | Transkript nicht gefunden — nicht als 0 lesen |")
        continue
    ctx, out = res
    if ctx >= stop:
        lage = "**STOPP** — an der Ticketgrenze Kontext leeren"
        stops.append(rolle)
    elif ctx >= warn:
        lage = "Warnung — kein neues Ticket mehr annehmen"
    else:
        lage = "ok"
    print(f"| {rolle} | `{sid}` | {num(ctx)} | {num(out)} | {lage} |")

print()
for rolle in stops:
    print(f"STOP {rolle}")
if not stops:
    print("_kein Stopp-Flag gesetzt_")
PY

echo "budget.md geschrieben:"
grep -E '^\| [a-z]' "$SPRINT/budget.md" || true
