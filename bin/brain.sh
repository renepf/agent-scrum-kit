#!/usr/bin/env bash
# Gedaechtnis je Rolle plus ein geteiltes Schwarmgedaechtnis. Sprint-unabhaengig:
# ueberlebt Kontext-Reset, Sessionwechsel und Sprintende. Regeln: memory/README.md
#
#   memory/<rolle>/INDEX.md            GENERIERT — alles, was diese Rolle weiss
#   memory/<rolle>/log.md              append-only Journal
#   memory/<rolle>/facts/<slug>.md     ein Fakt je Datei (Frontmatter)
#   memory/<rolle>/docs/<slug>.md      Arbeitsnotizen, ueberschreibbar
#   memory/<rolle>/handover/<zeit>.md  Uebergabe vor jedem Reset
#   memory/_shared/INDEX.md            GENERIERT — Schwarmwissen
#   memory/_shared/facts/<slug>.md     geteilter Fakt, nur der Autor aendert oder loescht ihn
#
#   brain.sh note <slug> "<beschreibung>"     < rumpf   TYPE=user|feedback|project|reference
#   brain.sh share <slug> "<beschreibung>"    < rumpf   (TYPE wie oben)
#   brain.sh forget <slug> [--shared]                   falsch gewordenen Fakt loeschen
#   brain.sh doc <slug> "<beschreibung>"      < rumpf
#   brain.sh handover "<beschreibung>"        < rumpf
#   brain.sh log "<betreff>"                  < rumpf
#   brain.sh recall                                     nach Reset: Index, letzte Uebergabe, Schwarm
#   brain.sh index                                      Indizes neu bauen
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

R="$(role)"
ME="$MEMORY_DIR/$R"
SHARED="$MEMORY_DIR/_shared"
mkdir -p "$ME/facts" "$ME/docs" "$ME/handover" "$SHARED/facts"

slug_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{1,60}$ ]] || die "Slug '$1' ungueltig: nur a-z, 0-9, Bindestrich, 2–61 Zeichen"; }

# Prueft einen neuen Fakt gegen die Regeln aus memory/README.md. Rumpf kommt ueber eine Datei.
# Exit != 0 mit Meldung, wenn eine Regel verletzt ist.
guard_fact() {
  local target="$1" slug="$2" desc="$3" type="$4" bodyfile="$5"
  python3 - "$MEMORY_DIR" "$target" "$slug" "$desc" "$type" "$bodyfile" <<'PY'
import glob, os, re, sys
mem, target, slug, desc, typ, bodyfile = sys.argv[1:7]
body = open(bodyfile, encoding="utf-8").read()

if typ not in ("user", "feedback", "project", "reference"):
    sys.exit(f"FEHLER: Typ '{typ}' ungueltig. Erlaubt: user | feedback | project | reference")
if not desc.strip():
    sys.exit("FEHLER: Beschreibung fehlt — sie ist die Zeile im Index, ohne sie findet niemand den Fakt")

# Relative Datumsangaben sind in drei Monaten falsch. Absolut schreiben.
REL = r"\b(heute|gestern|morgen|vorgestern|(ue|ü)bermorgen|letzte[nr]? (woche|monat)|n(ae|ä)chste[nr]? (woche|monat)|diese[nr]? woche|today|yesterday|tomorrow|last (week|month)|next (week|month)|this week)\b"
m = re.search(REL, (desc + "\n" + body).lower())
if m:
    sys.exit(f"FEHLER: relative Datumsangabe '{m.group(0)}' — in ein absolutes Datum umschreiben (YYYY-MM-DD)")

# Dublette: ein ANDERER Slug mit derselben Beschreibung. Denselben Slug zu ueberschreiben ist
# der gewollte Weg, einen Fakt zu aendern.
norm = lambda s: re.sub(r"\s+", " ", s.strip().lower())
for f in glob.glob(os.path.join(mem, "*", "facts", "*.md")):
    if os.path.abspath(f) == os.path.abspath(target):
        continue
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith("description:") and norm(line[12:]) == norm(desc):
            rel = os.path.relpath(f, mem)
            sys.exit(f"FEHLER: Dublette von memory/{rel} — dort aendern (gleicher Slug), keinen zweiten Eintrag anlegen")
PY
}

write_fm() {
  local target="$1" name="$2" desc="$3" type="$4" bodyfile="$5"
  {
    printf -- '---\nname: %s\ndescription: %s\ntype: %s\nauthor: %s\nupdated: %s\n---\n\n' \
      "$name" "$desc" "$type" "$R" "$(date '+%Y-%m-%d %H:%M')"
    cat "$bodyfile"
  } | atomic_write "$target"
}

# Index eines Ordners aus den Frontmattern bauen. Deterministisch, atomar, nie handgeschrieben.
build_index() {
  local root="$1" title="$2"
  python3 - "$root" "$title" "$MEMORY_DIR" <<'PY' | atomic_write "$root/INDEX.md"
import glob, os, re, sys
root, title, mem = sys.argv[1], sys.argv[2], sys.argv[3]
def fm(path):
    meta, body = {}, []
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    if lines and lines[0].strip() == "---":
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                body = lines[i + 1:]
                break
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
    return meta, "\n".join(body)

known = set()
for f in glob.glob(os.path.join(mem, "*", "facts", "*.md")):
    known.add(fm(f)[0].get("name", ""))

print(f"# {title}\n\nGENERIERT von bin/brain.sh. Nicht von Hand editieren. Eine Zeile je Eintrag.\n")
dangling = []
for kind, label in (("handover", "Uebergaben (neueste zuerst)"), ("facts", "Fakten"), ("docs", "Arbeitsdokumente")):
    d = os.path.join(root, kind)
    if not os.path.isdir(d):
        continue
    files = sorted((f for f in os.listdir(d) if f.endswith(".md")), reverse=(kind == "handover"))
    if not files:
        continue
    print(f"## {label}\n\n| Datei | Beschreibung | Typ | Autor | Stand | Verweise |\n|---|---|---|---|---|---|")
    for f in files:
        meta, body = fm(os.path.join(d, f))
        links = sorted(set(re.findall(r"\[\[([a-z0-9][a-z0-9-]*)\]\]", body)))
        dangling += [(f"{kind}/{f}", l) for l in links if l not in known]
        print(f"| [{kind}/{f}]({kind}/{f}) | {meta.get('description','-')} | {meta.get('type','-')} "
              f"| {meta.get('author','-')} | {meta.get('updated','-')} | {' '.join('[['+l+']]' for l in links) or '-'} |")
    print()
if dangling:
    print("## Offene Verweise\n\nKein Fehler: ein Verweis ohne Ziel markiert einen Fakt, der noch geschrieben werden sollte.\n")
    for src, l in dangling:
        print(f"- `[[{l}]]` in {src}")
    print()
log = os.path.join(root, "log.md")
if os.path.exists(log):
    heads = [(n, l.strip()[3:]) for n, l in enumerate(open(log, encoding="utf-8", errors="replace"), 1)
             if re.match(r"^## \d{4}-\d{2}-\d{2} \d{2}:\d{2} · ", l)]
    print(f"## Journal — letzte 20 von {len(heads)}\n")
    for n, h in heads[-20:][::-1]:
        print(f"- [log.md:{n}](log.md) {h}")
    print()
PY
}

reindex() { build_index "$ME" "Gedaechtnis · $R"; build_index "$SHARED" "Schwarmgedaechtnis · alle Rollen"; }

BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT

cmd="${1:-}"; shift || true
case "$cmd" in
  note|share)
    [ $# -ge 2 ] || die "Aufruf: brain.sh $cmd <slug> \"<beschreibung>\" < rumpf"
    slug_ok "$1"; cat > "$BODY"
    if [ "$cmd" = "note" ]; then target="$ME/facts/$1.md"; else target="$SHARED/facts/$1.md"; fi
    if [ "$cmd" = "share" ] && [ -f "$target" ]; then
      owner="$(sed -n 's/^author: //p' "$target" | head -1)"
      [ "$owner" = "$R" ] || die "$1 gehoert $owner. Nicht ueberschreiben — eigenen Slug waehlen oder @$owner im Chat bitten"
    fi
    guard_fact "$target" "$1" "$2" "${TYPE:-project}" "$BODY" || exit 1
    write_fm "$target" "$1" "$2" "${TYPE:-project}" "$BODY"
    reindex; echo "gemerkt: ${target#$KIT_ROOT/}"
    ;;
  forget)
    [ $# -ge 1 ] || die "Aufruf: brain.sh forget <slug> [--shared]"
    slug_ok "$1"
    if [ "${2:-}" = "--shared" ]; then target="$SHARED/facts/$1.md"; else target="$ME/facts/$1.md"; fi
    [ -f "$target" ] || die "${target#$KIT_ROOT/} gibt es nicht — nichts geloescht"
    owner="$(sed -n 's/^author: //p' "$target" | head -1)"
    [ "$owner" = "$R" ] || die "$1 gehoert $owner — nur der Autor loescht"
    rm -f "$target"; reindex; echo "geloescht: ${target#$KIT_ROOT/}"
    ;;
  doc)
    [ $# -ge 2 ] || die "Aufruf: brain.sh doc <slug> \"<beschreibung>\" < rumpf"
    slug_ok "$1"; cat > "$BODY"; write_fm "$ME/docs/$1.md" "$1" "$2" "doc" "$BODY"
    reindex; echo "dokument: memory/$R/docs/$1.md"
    ;;
  handover)
    [ $# -ge 1 ] || die "Aufruf: brain.sh handover \"<beschreibung>\" < rumpf"
    cat > "$BODY"; f="$(date '+%Y-%m-%d-%H%M%S').md"
    write_fm "$ME/handover/$f" "handover-${f%.md}" "$1" "handover" "$BODY"
    reindex; echo "uebergabe: memory/$R/handover/$f"
    ;;
  log)
    [ $# -ge 1 ] || die "Aufruf: brain.sh log \"<betreff>\" < rumpf"
    cat > "$BODY"
    append() {
      [ -f "$ME/log.md" ] || printf '# Journal · %s\n\nAppend-only. Nie editieren — der Index verweist auf Zeilennummern.\n' "$R" > "$ME/log.md"
      { printf '\n## %s · %s · %s\n' "$(now)" "$R" "$1"; cat "$BODY"; } >> "$ME/log.md"
    }
    with_lock "$ME/log.md.lock" append "$1"
    reindex; echo "journal: memory/$R/log.md:$(wc -l < "$ME/log.md" | tr -d ' ')"
    ;;
  recall)
    reindex
    echo "══ dein Gedaechtnis: memory/$R/INDEX.md ══"; sed -n '4,60p' "$ME/INDEX.md"
    last="$(ls -1 "$ME/handover/"*.md 2>/dev/null | sort | tail -1 || true)"
    if [ -n "$last" ]; then echo "══ letzte Uebergabe: ${last#$KIT_ROOT/} ══"; sed -n '1,80p' "$last"
    else echo "══ keine Uebergabe vorhanden ══"; fi
    echo "══ Schwarm: memory/_shared/INDEX.md ══"; sed -n '4,40p' "$SHARED/INDEX.md"
    ;;
  index) reindex; echo "Indizes neu gebaut: memory/$R, memory/_shared" ;;
  *) die "Befehl: note | share | forget | doc | handover | log | recall | index" ;;
esac
