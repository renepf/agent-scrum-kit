#!/usr/bin/env bash
# UNKNOWN — the place and the format of the cursor transcripts are not measured.
# Failing is the right answer here: budget.md records UNKNOWN and the
# role falls back to the emergency brake (retirement after KIT_MAX_TICKETS tickets).
echo "UNKNOWN — no transcripts known for cursor. To check under ~/.cursor/" >&2
exit 1
