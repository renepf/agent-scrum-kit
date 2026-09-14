#!/usr/bin/env bash
# Rolle + Session-ID in roster.md eintragen und die Rolle fuer DIESE Instanz sperren.
# Beim Start jeder Session, nach jedem Reset — tick.sh ruft es bei Bedarf selbst.
#
#   export KIT_ROLE=engineer-a
#   bin/register.sh                 # Session-ID vom Host-Adapter
#   bin/register.sh <session-id>    # oder explizit
#
# Zwillingssperre (Lease): je Rolle eine Datei sprints/<aktiv>/.lease-<rolle> mit
# Session-ID, Host-PID und Zeit. Laeuft bereits eine ANDERE lebende Instanz derselben Rolle,
# bricht register.sh ab. Anlass: eine Session wurde zweimal fortgesetzt, zwei Prozesse
# derselben Rolle arbeiteten parallel — owner:<rolle> trennt Rollen, nicht Zwillinge.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPRINT="$(sprint_dir)"
R="$(role)"
SID="${1:-$(session_id)}"
ROSTER="$SPRINT/roster.md"
LEASE="$SPRINT/.lease-$R"
HPID="$(host_pid)"
NOW_EPOCH="$(date +%s)"

check_lease() {
  if [ -f "$LEASE" ]; then
    local l_sid l_pid l_epoch age
    IFS='|' read -r l_sid l_pid l_epoch < "$LEASE" || true
    age=$(( NOW_EPOCH - ${l_epoch:-0} ))
    if [ "$age" -lt $(( KIT_LEASE_MINUTES * 60 )) ] && host_alive "$l_pid"; then
      if [ -z "$HPID" ]; then
        echo "WARNUNG: Host-PID UNKNOWN (adapters/$KIT_HOST/host-pid.sh) — Zwillingssperre kann nicht pruefen, ob PID $l_pid dieselbe Instanz ist." >&2
      elif [ "$l_pid" != "$HPID" ]; then
        die "zweite Instanz von '$R': Host-PID $l_pid (Session $l_sid) laeuft noch und tickte vor $((age / 60)) min. Diese Instanz (PID $HPID, Session $SID) beenden — zwei Prozesse derselben Rolle arbeiten sonst parallel."
      fi
    fi
  fi
  printf '%s|%s|%s\n' "$SID" "${HPID:--}" "$NOW_EPOCH" | atomic_write "$LEASE"
}

write_roster() {
  local body
  body="$( { [ -f "$ROSTER" ] && grep '^| 2' "$ROSTER" | grep -v "^| [^|]* | $R | " || true; } )"
  {
    printf '# roster · %s\n\n' "$(basename "$SPRINT")"
    printf 'GENERIERT von bin/register.sh. Eine Zeile je Rolle, juengster Eintrag gilt.\n\n'
    printf '| Zeit | Rolle | Session-ID | Host | Host-PID |\n|---|---|---|---|---|\n'
    [ -n "$body" ] && printf '%s\n' "$body"
    printf '| %s | %s | %s | %s | %s |\n' "$(now)" "$R" "$SID" "$KIT_HOST" "${HPID:-UNKNOWN}"
  } | atomic_write "$ROSTER"
}

# Zwei Sperren, nacheinander, nie verschachtelt:
#   $LEASE.lock   — je Rolle: zwei Zwillinge, die im selben Moment starten, bestehen nicht beide.
#   $ROSTER.lock  — fuer alle Rollen: roster.md ist geteilt. Mit nur der Rollen-Sperre verloren neun
#                   gleichzeitig startende Sessions 5 von 9 Zeilen (Starttest 2026-09-14).
# Nicht verschachtelt, weil with_lock seine Aufraeum-trap setzt: eine innere Sperre ueberschreibt die
# trap der aeusseren, und ein die() in der Zwillingspruefung liess dann die Lease-Sperre liegen.
with_lock "$LEASE.lock" check_lease
with_lock "$ROSTER.lock" write_roster
anchor_role "$R"

echo "$R registriert · session $SID · host $KIT_HOST · pid ${HPID:-UNKNOWN}"
