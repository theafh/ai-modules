#!/usr/bin/env bash
# Eval 7 fixture: ambiguous same-path drift.
#
# Reuses eval 6's detached-writer idea with one change: both the
# pre-existing dirty state and the background write target a path that is
# ALREADY present in the reviewed-set baseline. seed.txt is dirtied before
# the agent starts, so it appears in the <status_after_staging_new_files>
# snapshot; the detached writer then re-edits that SAME path mid-run. No
# path outside the baseline newly appears, so the drift check cannot tell
# foreign drift from this session's own further edit — the ambiguous case.
# git_commit's tiebreaker must commit all (no pause) and the commit must
# include that path's latest content, proving no file is silently dropped.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"
target="$(cd "$target" && pwd)"

# Pre-dirty a tracked file so it is already present (as modified) in the
# reviewed-set baseline the script captures.
(
    cd "$target"
    printf 'baseline dirty edit\n' > seed.txt
)

# The concurrent session re-edits that SAME tracked file after a fixed
# delay, appending a distinctive marker line. Because seed.txt is already
# in the baseline, no path outside it newly appears (the ambiguous case).
# The marker lets the grader confirm the further edit was swept in
# (no-miss) rather than dropped. Detach and size the delay exactly as the
# concurrent_drift fixture does; see GIT_COMMIT_DRIFT_DELAY there.
delay="${GIT_COMMIT_DRIFT_DELAY:-20}"
marker='CONCURRENT_APPEND_MARKER'
seedfile="$target/seed.txt"
nohup bash -c "sleep $delay; printf '%s\n' '$marker' >> '$seedfile'" \
    >/dev/null 2>&1 &

echo "Eval 7 sandbox staged at $target"
echo "  baseline-dirty file: seed.txt (already in the reviewed-set baseline)"
echo "  detached writer appends '$marker' to seed.txt after ${delay}s (same-path drift)"
