#!/usr/bin/env bash
CASE_DESC="alle 40 unerlaubten Uebergaenge werden als Kante abgelehnt und lassen den Zustand unveraendert"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null

# Alle Paare aus den Zustaenden, die nicht in protocols/LOOP.md als Kante stehen.
STATES="backlog planned in-progress rfr in-review rft in-testing"
ALLOWED=" backlog>planned planned>in-progress in-progress>rfr rfr>in-review in-review>rft in-review>in-progress rft>in-testing in-testing>in-progress in-testing>done "
# Die Rolle ist je Ziel die zustaendige — so kann nur die KANTE die Ablehnung erklaeren.
rolle_fuer() {
  case "$1" in
    backlog|planned|done) echo product-owner ;; in-progress|rfr) echo engineer-a ;;
    in-review|rft) echo qa-ruthless ;; in-testing) echo acceptance-tester ;;
  esac
}

nr=100; abgelehnt=0; gesamt=0; durch=""
for von in $STATES; do
  for nach in $STATES done; do
    [ "$von" = "$nach" ] && continue
    case "$ALLOWED" in *" $von>$nach "*) continue ;; esac
    nr=$((nr + 1)); gesamt=$((gesamt + 1))
    sandbox_ticket "$nr" "$von"
    vorher="$(sandbox_labels "$nr")"
    # Ausgabe erst einfangen: unter pipefail waere "status.sh | grep" falsch, sobald status.sh
    # wie gewollt mit Exit 1 abbricht — auch wenn grep die Meldung findet.
    out="$(KIT_ROLE="$(rolle_fuer "$nach")" "$BIN/status.sh" "$nr" "$nach" "eval" 2>&1)"
    nachher="$(sandbox_labels "$nr")"
    # Zwei Achsen: die Meldung UND der unveraenderte Zustand. Nur eine davon zu pruefen liess eine
    # abgeschaltete Kantensperre gruen durch (Mutationsprobe 2026-09-10).
    if case "$out" in *"unerlaubter Uebergang"*) true ;; *) false ;; esac && [ "$vorher" = "$nachher" ]; then
      abgelehnt=$((abgelehnt + 1))
    else
      durch="$durch $von>$nach"
    fi
  done
done
observe "$abgelehnt/$gesamt als Kante abgelehnt, Zustand unveraendert${durch:+ · nicht korrekt abgelehnt:$durch}"
echo "BEOBACHTET: $OBSERVED"
[ "$abgelehnt" = "$gesamt" ] && [ "$gesamt" = 40 ]   # 7 Ausgangszustaende x 7 Ziele − 9 erlaubte Kanten
