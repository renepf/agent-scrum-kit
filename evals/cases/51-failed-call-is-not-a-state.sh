#!/usr/bin/env bash
CASE_DESC="a failed tool call is never read as a state"
CASE_KIND="static"
CASE_HOST=""
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
sandbox; trap sandbox_cleanup EXIT
sandbox_sprint > /dev/null
sandbox_ticket 5 planned
export KIT_ROLE=engineer-a

before="$("$BIN/tickets.sh" labels 5 | tr '\n' ' ')"

# The backend fails: preflight must fail and status.sh must abort,
# without touching the label and without concluding "it must already be done".
cat > "$SANDBOX/broken.env" <<ENV
$(cat "$SANDBOX/kit.env")
KIT_ISSUE_BACKEND="gh"
KIT_REPO="eval/does-not-exist"
ENV
export PATH="$SANDBOX/fakebin:$PATH"
mkdir -p "$SANDBOX/fakebin"
printf '#!/usr/bin/env bash\necho "HTTP 503: service unavailable" >&2\nexit 1\n' > "$SANDBOX/fakebin/gh"
chmod +x "$SANDBOX/fakebin/gh"

out="$(KIT_ENV_FILE="$SANDBOX/broken.env" "$BIN/status.sh" 5 in-progress "versuch" 2>&1)"; rc=$?
after="$(KIT_ENV_FILE="$SANDBOX/kit.env" "$BIN/tickets.sh" labels 5 | tr '\n' ' ')"

errors=""
[ "$rc" != 0 ] || errors="$errors status.sh-did-not-abort"
[ "$before" = "$after" ] || errors="$errors label-changed($before->$after)"
case "$out" in *ERROR*) ;; *) errors="$errors no-error-message" ;; esac

observe "exit code $rc · label before '$before' after '$after' · message: $(echo "$out" | tail -1 | cut -c1-60)${errors:+ · ERRORS:$errors}"
echo "OBSERVED: $OBSERVED"
[ -z "$errors" ]
