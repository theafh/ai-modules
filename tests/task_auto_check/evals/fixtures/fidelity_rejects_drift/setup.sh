#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/src/api" "$target/proj/tests"

# The API request path exists and resolves an authenticated user id before
# dispatch, so the per-user premise holds and the run reaches the rate-limit
# repair instead of an invalidated-premise stop.
cat > "$target/proj/src/api/auth.py" <<'EOF'
"""Resolve the authenticated user for a public API request."""

API_KEYS = {"key-alice": "user-alice", "key-bob": "user-bob"}


def authenticated_user_id(request):
    """Return the user id behind the request's API key, or None."""
    return API_KEYS.get(request.get("headers", {}).get("X-API-Key"))
EOF

cat > "$target/proj/src/api/request_path.py" <<'EOF'
"""Public API request path: authenticate, then dispatch to the route handler."""

from src.api.auth import authenticated_user_id


def handle_public_request(request, handler):
    """Serve one public API request on behalf of its authenticated user."""
    user_id = authenticated_user_id(request)
    if user_id is None:
        return {
            "status": 401,
            "headers": {"Content-Type": "application/json"},
            "body": '{"error": "unauthorized"}',
        }
    request["user_id"] = user_id
    return handler(request)
EOF

cat > "$target/proj/tests/test_request_path.py" <<'EOF'
from src.api.request_path import handle_public_request


def echo_user(request):
    return {"status": 200, "headers": {}, "body": request["user_id"]}


def test_authenticated_request_reaches_handler():
    response = handle_public_request({"headers": {"X-API-Key": "key-alice"}}, echo_user)
    assert response["status"] == 200
    assert response["body"] == "user-alice"


def test_unauthenticated_request_is_rejected():
    response = handle_public_request({"headers": {}}, echo_user)
    assert response["status"] == 401
EOF

cat > "$target/proj/tasks/api_rate-limit.md" <<'EOF'
---
description: Clarify a per-user API rate-limit task without broadening it.
scope: "api"
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
status: open
reported-by: Harness
---

# Per-user API rate limit

## Goal

Throttle each authenticated user to 100 public API requests per minute.

## Context

The current task needs clearer acceptance checks. This is not a global abuse-prevention redesign.

## Approach

Add a per-user fixed-window rate-limit check to the API request path.

## Acceptance

- The API is protected from abusive clients.
EOF

commit_proj "$target"
