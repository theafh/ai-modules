#!/usr/bin/env bash
# between_turns.sh <target> <proj> — the user's approval answer arrives here, so
# the resumed turn reads it from the run directory rather than from its prompt.

set -euo pipefail
proj="${2:?proj dir required}"
cat > "$proj/.agent_spinner/answer.txt" <<'ANSWER'
writer-scope: approved for all five pages under notes/. The family writer
(notes_repairer) may repair every page it found a defect on.
ANSWER
