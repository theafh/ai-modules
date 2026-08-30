#!/usr/bin/env bash
# labeled-why-open fixture: the fork no tier settles.
#
# The project carries the harness rule file and nothing else — no family
# guardrail docs, no wiki, an empty backlog with no archived precedent — and the
# code is silent on the fork. The create prompt leaves a call the user reserves
# for themselves: whether a permanently dead endpoint gets auto-disabled or
# retried forever. The base **Decide or label** evidence base cannot reach a
# call resting on the user's own risk appetite, so the "insufficient evidence"
# ground of the why-open test qualifies. The written task must carry exactly one
# labeled "Open decision:" naming its options, a suggested default, and why the
# evidence leaves it open, and the create path must surface it to the user in
# its **Offer open-decision reconciliation** step rather than leaving it to rest
# in the file alone.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

## Repo rules

The hooks package is plain Python with no build step. Cite a standing repo rule
from a task rather than copying its text into the task body.
EOF

mkdir -p "$proj/src/hooks"

cat > "$proj/src/hooks/sender.py" <<'EOF'
"""Outbound webhook delivery.

A delivery is attempted exactly once. There is no retry, no backoff, and no
per-endpoint failure bookkeeping anywhere in this package.
"""

import json
import urllib.request

TIMEOUT_S = 5


def send(endpoint, payload):
    """POST payload to endpoint. Returns the HTTP status, or None on failure."""
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        endpoint.url, data=body, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            return resp.status
    except OSError:
        return None
EOF

cat > "$proj/src/hooks/registry.py" <<'EOF'
"""Registered webhook endpoints.

An endpoint is either present or absent. There is no enabled flag, no failure
counter, and no lifecycle beyond registration and removal.
"""


class Endpoint:
    def __init__(self, name, url):
        self.name = name
        self.url = url


REGISTERED = {}


def register(name, url):
    REGISTERED[name] = Endpoint(name, url)


def unregister(name):
    REGISTERED.pop(name, None)
EOF

echo "labeled-why-open sandbox staged at $proj"
