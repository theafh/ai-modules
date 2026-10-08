#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# Same clean-premise staging as regroup_immediate_ready: every span the task's
# claims rest on exists, so a first-call gate can clear the whole checklist and
# stamp ready without raising an issue. What this fixture changes is where the
# repeat sits. Both links fall inside one Context paragraph, so the material is
# already gathered and the repeated-link repair round can only apply the react
# protocol's one-paragraph case: the Grouping advocate names the sibling again
# in plain text inside that paragraph, and the verifier approves that edit
# rather than rejecting it as link stripping.
cat > "$target/proj/src/api/throttle.py" <<'EOF'
"""Request throttling. Emits HTTP 429 when a client exceeds its budget."""

THROTTLE_WINDOW_SECONDS = 60


def build_throttle_response():
    """Return the HTTP 429 response sent to a throttled client."""
    return {
        "status": 429,
        "headers": {"Content-Type": "application/json"},
        "body": '{"error": "too many requests"}',
    }
EOF

cat > "$target/proj/tests/test_throttle.py" <<'EOF'
from src.api.throttle import build_throttle_response


def test_throttled_response_is_429():
    response = build_throttle_response()
    assert response["status"] == 429


def test_throttled_response_body_names_the_error():
    response = build_throttle_response()
    assert "too many requests" in response["body"]
EOF

cat > "$target/proj/docs/api.md" <<'EOF'
# API reference

## Response headers

- `Content-Type` gives the media type of the response body.
- `X-Request-Id` echoes the request identifier when the client sent one.

## Throttling

Clients exceeding their request budget receive HTTP 429 with a JSON error
body built by `build_throttle_response()`.
EOF

# The sibling the target links twice. Its own body says nothing about the
# target, so the regroup has no reason to touch this file.
cat > "$target/proj/tasks/api_throttle-window-config.md" <<'EOF'
---
description: Move the throttle window constant out of src/api/throttle.py into the service config so operators can tune it without a deploy.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Throttle window moves into service config

## Goal

Move `THROTTLE_WINDOW_SECONDS` out of `src/api/throttle.py` into the service
config so operators tune the throttle window without a deploy.

## Context

`src/api/throttle.py` hard-codes `THROTTLE_WINDOW_SECONDS = 60` at module
scope. Every caller reads the constant directly.

## Approach

Read the window from the service config with the current value as its
default, and leave the module-level name as a thin accessor.

## Acceptance

- `src/api/throttle.py` reads the throttle window from the service config.
- Overriding the window in the config changes the value the throttle module
  reports, proven by a pytest case in `tests/test_throttle.py`.
EOF

# Target task. One Context paragraph carries the whole account of the handoff,
# that the sibling task is moving the window constant into config, and links
# the sibling twice. Approach reads the window without naming the sibling, so
# nothing outside that paragraph needs to move.
cat > "$target/proj/tasks/api_retry-header.md" <<'EOF'
---
description: Add a Retry-After header to API throttling responses so clients know when to retry after HTTP 429.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Retry-After header on throttling responses

## Goal

Add a `Retry-After` response header to API throttling responses so clients
know when to retry after HTTP 429.

## Context

`src/api/throttle.py` builds the HTTP 429 response in
`build_throttle_response()`, which today returns only `Content-Type` in its
headers. The module's `THROTTLE_WINDOW_SECONDS = 60` names the throttle
window, and
[api_throttle-window-config](api_throttle-window-config.md) is moving that
constant into the service config, so this task reads the window through the
module-level name and leaves the config move to
[api_throttle-window-config](api_throttle-window-config.md). `docs/api.md`
documents public response headers under its `## Response headers` section,
which does not yet list `Retry-After`. `tests/test_throttle.py` covers the
current 429 response with pytest.

## Approach

Update `build_throttle_response()` to include `Retry-After` in its headers,
valued as `THROTTLE_WINDOW_SECONDS` in seconds and read through the
module-level name rather than inlining 60. Then document the header in the
`## Response headers` section of `docs/api.md`.

## Acceptance

- A pytest test added to the existing `tests/test_throttle.py` confirms the
  throttled response carries HTTP 429 and a `Retry-After` header value equal
  to `THROTTLE_WINDOW_SECONDS`.
- `docs/api.md` lists `Retry-After` under its `## Response headers` section.
EOF

commit_proj "$target"
