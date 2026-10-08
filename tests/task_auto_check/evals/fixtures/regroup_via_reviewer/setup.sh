#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# The premise is true in the staged code, so the gate reaches the ordinary
# repair path rather than the invalidated-premise stop: the quota module builds
# its 402 response with no Retry-After header and the docs list no such header.
cat > "$target/proj/src/api/quota.py" <<'EOF'
"""Monthly request quota. Emits HTTP 402 once a tenant exhausts its budget."""

QUOTA_RESET_SECONDS = 3600


def build_quota_response(remaining):
    """Return the response for a quota check, 402 once the budget is gone."""
    if remaining > 0:
        return {"status": 200, "headers": {"Content-Type": "application/json"}}
    return {
        "status": 402,
        "headers": {"Content-Type": "application/json"},
        "body": '{"error": "quota exhausted"}',
    }
EOF

cat > "$target/proj/tests/test_quota.py" <<'EOF'
from src.api.quota import build_quota_response


def test_exhausted_quota_is_402():
    assert build_quota_response(0)["status"] == 402


def test_remaining_quota_is_200():
    assert build_quota_response(5)["status"] == 200
EOF

cat > "$target/proj/docs/api.md" <<'EOF'
# API reference

## Response headers

- `Content-Type` gives the media type of the response body.

## Quota

A tenant that exhausts its monthly budget receives HTTP 402 with a JSON error
body built by `build_quota_response()`.
EOF

# The sibling the target links twice. Nothing in this file points back, so the
# regroup has no reason to edit it and the grader can hold it byte-identical.
cat > "$target/proj/tasks/api_quota-reset-config.md" <<'EOF'
---
description: Move the quota reset interval out of src/api/quota.py into the service config so operators can tune it without a deploy.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Quota reset interval moves into service config

## Goal

Move `QUOTA_RESET_SECONDS` out of `src/api/quota.py` into the service config
so operators tune the reset interval without a deploy.

## Context

`src/api/quota.py` hard-codes `QUOTA_RESET_SECONDS = 3600` at module scope.
Every caller reads the constant directly.

## Approach

Read the reset interval from the service config with the current value as its
default, and leave the module-level name as a thin accessor.

## Acceptance

- `src/api/quota.py` reads the reset interval from the service config.
- Overriding the interval in the config changes the value the quota module
  reports, proven by a pytest case in `tests/test_quota.py`.
EOF

# Target task. Two defects ride together on purpose. Context and Approach carry
# the SAME account of one handoff (the sibling task moving the reset constant
# into config), each with its own link, so that material belongs in one
# passage and the react protocol gathers it under one link. Separately,
# Approach promises the 200 path leaves the header off and no Acceptance item
# proves it, which is the gate-visible readiness issue that opens an ordinary
# repair round for the regroup to ride.
cat > "$target/proj/tasks/api_quota-retry-header.md" <<'EOF'
---
description: Add a Retry-After header to API quota-exhausted responses so clients know when the monthly budget resets.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Retry-After header on quota-exhausted responses

## Goal

Add a `Retry-After` response header to API quota-exhausted responses so a
client knows when its monthly budget resets after HTTP 402.

## Context

`src/api/quota.py` builds the HTTP 402 response in `build_quota_response()`,
which today returns only `Content-Type` in its headers. The module's
`QUOTA_RESET_SECONDS = 3600` names the reset interval, and
[api_quota-reset-config](api_quota-reset-config.md) is moving that constant
into the service config. `docs/api.md` documents public response headers
under its `## Response headers` section, which does not yet list
`Retry-After`. `tests/test_quota.py` covers both quota branches with pytest.

## Approach

Update `build_quota_response()` to include `Retry-After` in the headers of
its 402 branch, valued as `QUOTA_RESET_SECONDS` in seconds, and leave the 200
branch's headers as they are. That constant is being moved into the service
config by [api_quota-reset-config](api_quota-reset-config.md), so read it
through the module-level name rather than inlining 3600. Then document the
header in the `## Response headers` section of `docs/api.md`.

## Acceptance

- A pytest case in `tests/test_quota.py` confirms the exhausted-quota
  response carries HTTP 402 and a `Retry-After` header value equal to
  `QUOTA_RESET_SECONDS`.
- `docs/api.md` lists `Retry-After` under its `## Response headers` section.
EOF

commit_proj "$target"
