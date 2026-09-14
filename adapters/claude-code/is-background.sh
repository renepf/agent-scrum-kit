#!/usr/bin/env bash
# Exit 0, wenn diese Session eine Hintergrund-Session ist, die KIT_ROLE nur geerbt hat.
# claude startet unter einer Rolle z.B. "claude daemon run --origin transient" mit
# CLAUDE_CODE_SESSION_KIND=bg (Referenz-Loop 2026-09-14 15:32); der Hook weckte sie als Rolle.
# NICHT CLAUDE_CODE_CHILD_SESSION pruefen: das steht in der Werkzeug-Umgebung JEDER Session.
[ "${CLAUDE_CODE_SESSION_KIND:-}" = "bg" ]
