#!/usr/bin/env bash
# fix_coherence_selector_explicit_list fixture: four live tasks in one scope,
# sized for the explicit-list selector form. The prompt names two of them by
# path, so the assessment must cover exactly those two and leave the other two
# out of the selected live set even though they sit in the same scope and share
# the same target file.
#
# Sharing one target file across all four is deliberate: it rules out a pass
# that narrows by target artifact rather than by the list the user named.
#
# The prompt asks for the assessment in coherence-report.md as well as in the
# response, because grade.sh never sees the agent's response text; the report
# file is what makes the selected-set boundary deterministically gradeable.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/svc"

cat > "$proj/svc/client.py" <<'EOF'
"""Outbound HTTP client with retry and timeout policy."""

RETRIES = 3
TIMEOUT_S = 10


def call(url):
    return {"url": url, "retries": RETRIES, "timeout_s": TIMEOUT_S}
EOF

seed_task() {
    local name="$1" title="$2" goal="$3" approach="$4" acc="$5"
    cat > "$proj/tasks/$name" <<EOF
---
description: $goal
scope: svc
created: $now
updated: $now
status: ready
reported-by: Test User
---

# $title

## Goal

$goal

## Context

[svc/client.py](../svc/client.py) holds the retry and timeout policy.

## Approach

$approach

## Acceptance

- $acc
EOF
}

seed_task svc_alpha-retry.md "Back off between retries" \
    "Retries wait an exponential backoff between attempts instead of firing back to back." \
    "Add a backoff computation to the retry loop in svc/client.py, doubling the wait per attempt." \
    "The retry loop waits a doubling interval between attempts."

seed_task svc_beta-retry.md "Cap the retry count" \
    "The retry count is capped at a configurable maximum so a caller cannot request an unbounded retry budget." \
    "Clamp the RETRIES value in svc/client.py to a declared maximum and reject a larger request." \
    "A caller requesting more than the declared maximum gets the clamped count."

seed_task svc_gamma-timeout.md "Split the connect and read timeouts" \
    "The client carries separate connect and read timeouts so a slow handshake fails faster than a slow body." \
    "Replace TIMEOUT_S in svc/client.py with a connect timeout and a read timeout." \
    "svc/client.py exposes a connect timeout and a read timeout separately."

seed_task svc_delta-timeout.md "Log a timeout with its elapsed time" \
    "A timed-out call logs the elapsed time it consumed, so a reader can tell a fast failure from a full-timeout stall." \
    "Record the elapsed time in the timeout path of svc/client.py and include it in the log line." \
    "A timed-out call's log line names the elapsed time."

git_commit_all "$proj" "seed: one-scope backlog for the explicit-list selector"

echo "fix_coherence_selector_explicit_list sandbox staged at $proj"
