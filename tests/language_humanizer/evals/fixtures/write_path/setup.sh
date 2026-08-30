#!/usr/bin/env bash
# setup.sh — stage the write_path fixture (write path).
#
# Usage: setup.sh <target_dir>
#
# Writes <target_dir>/proj/notes.md: unordered retro notes, no document
# structure, carrying five load-bearing items among the noise —
#
#   1. owner     Dana Okoro (alerting rework)
#   2. owner     Marco Weiss (postmortem template refresh)
#   3. deadline  30 April
#   4. threshold 2 hours of downtime per quarter (error budget, with unit)
#   5. must      the error budget bar is a must, not a target
#
# plus two genuine open questions the notes never settle.

set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target/proj"
proj="$(cd "$target/proj" && pwd)"

cat >"$proj/notes.md" <<'EOF'
# raw notes — incident follow-ups (unordered, straight off the retro whiteboard)

- error budget: must not exceed 2 hours of downtime per quarter — hard bar, came from the SLO doc
- Dana Okoro — owns the alerting rework
- someone asked about the runbook, unclear who updates it
- alert noise: 40% of pages last month were duplicates
- deadline for the alerting rework: 30 April
- Marco Weiss — owns the postmortem template refresh
- p95 page-ack time is 11 minutes today, we want it under 5
- the retro itself ran long, lots of side discussion about tooling
- open: do we need a second on-call rotation? nobody decided
EOF

printf '%s\n' "$proj"
