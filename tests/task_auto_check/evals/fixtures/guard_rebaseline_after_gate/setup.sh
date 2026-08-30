#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# The staged repo supplies the evidence base the repairs draw on: the write
# path genuinely lacks Idempotency-Key handling (the task's gap), the docs
# carry the section the repair targets, and an existing pytest module anchors
# any test-shaped acceptance. Without this evidence the reviewers face an
# open design decision no code can settle, and the loop correctly stops for
# a human instead of reaching ready.
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Writes

Documented write behavior appears here.
EOF

cat > "$target/proj/src/api/writes.py" <<'EOF'
def handle_write(request):
    """Apply an API write request and return the created result."""
    return {"status": 201, "body": '{"result": "created"}'}
EOF

cat > "$target/proj/tests/test_writes.py" <<'EOF'
from src.api.writes import handle_write


def test_write_returns_created():
    response = handle_write({"body": "{}"})
    assert response["status"] == 201
EOF

cat > "$target/proj/tasks/api_idempotency.md" <<'EOF'
---
description: Reject repeated API writes that reuse an Idempotency-Key header.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Idempotency-Key for API writes

## Goal

Reject a repeated API write that reuses an `Idempotency-Key` request header, so a retried request cannot apply twice.

## Context

The implementation lives in the API write path.

## Approach

TBD.

## Acceptance

- The idempotency behavior works properly.
EOF

commit_proj "$target"
