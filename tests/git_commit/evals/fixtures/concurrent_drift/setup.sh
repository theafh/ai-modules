#!/usr/bin/env bash
# Eval 6 fixture: foreign drift from a concurrent session.
#
# A detached background writer drops a NEW file into the working tree
# mid-run — after prepare_commit_context.sh has captured the reviewed-set
# baseline, but before the skill's commit-time drift re-check. That new
# path is outside the baseline, so git_commit's drift guard must surface
# it and PAUSE rather than sweeping it into the commit silently.
#
# This is a deterministic stand-in for a real second session: no actual
# concurrent agent runs — just one detached, delayed file write.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"
target="$(cd "$target" && pwd)"

# The in-session work the agent legitimately reviews and means to commit:
# one modified tracked file plus a few new files. A modest multi-file set
# lengthens the agent's consume+compose phase, widening the window between
# the baseline capture and the commit-time drift re-check.
(
    cd "$target"
    printf 'in-session edit\n' > seed.txt
    printf 'session note a\n' > session_a.txt
    printf 'session note b\n' > session_b.txt
    printf 'session note c\n' > session_c.txt
)

# The concurrent session: a detached writer that, after a fixed delay,
# drops a NEW file the agent never reviewed. `nohup ... &` fully detaches
# it so it outlives setup.sh and stage.sh and fires during the agent's
# run (setsid is the Linux equivalent; macOS has no setsid by default).
#
# Sizing: the delay must land the file AFTER prepare_commit_context.sh
# runs (an early, front-loaded step, ~10s into a turn) yet BEFORE the
# commit-time re-check (the last model step before committing, typically
# 30s+ into a turn). The default 20s sits in that window with margin on
# both sides — not a tight race. Tune GIT_COMMIT_DRIFT_DELAY if the
# worker's latency differs (raise it if the file gets baselined; lower it
# if the agent commits before the file lands).
delay="${GIT_COMMIT_DRIFT_DELAY:-20}"
foreign="$target/concurrent_reorg.txt"
nohup bash -c "sleep $delay; printf 'concurrent session in-flight file\n' > '$foreign'" \
    >/dev/null 2>&1 &

echo "Eval 6 sandbox staged at $target"
echo "  in-session files: seed.txt, session_a.txt, session_b.txt, session_c.txt"
echo "  detached writer creates $foreign after ${delay}s (foreign drift)"
