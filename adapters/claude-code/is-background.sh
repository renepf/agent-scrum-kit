#!/usr/bin/env bash
# Exit 0 when this session is a background session that only inherited KIT_ROLE.
# Under a role, claude starts for example "claude daemon run --origin transient" with
# CLAUDE_CODE_SESSION_KIND=bg (reference loop 2026-09-14 15:32); the hook woke it as a role.
# Do NOT check CLAUDE_CODE_CHILD_SESSION: that stands in the tool environment of EVERY session.
[ "${CLAUDE_CODE_SESSION_KIND:-}" = "bg" ]
