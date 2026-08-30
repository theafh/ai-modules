#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Errors

Documented error behavior appears here.
EOF
# The staged code makes the task's premise true: errors.py builds the JSON
# error envelope with the code, message, and request-id fields the task
# Context and Approach describe, so the premise check clears and the wikilink
# stays the only mechanical finding.
cat > "$target/proj/src/api/errors.py" <<'EOF'
ERROR_CODE_PREFIX = "API"


def build_error_envelope(code, message, request_id):
    """Return the JSON error envelope: code, message, request-id."""
    return {
        "code": f"{ERROR_CODE_PREFIX}-{code}",
        "message": message,
        "request-id": request_id,
    }
EOF

# Sibling task that makes the wikilink target determinable: the only on-disk
# match for `api_error-codes` is this file.
cat > "$target/proj/tasks/api_error-codes.md" <<'EOF'
---
description: Enumerate the canonical API error codes returned across endpoints.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# API error code catalog

## Goal

Enumerate the canonical machine-readable API error codes shared across endpoints.

## Context

`src/api/errors.py` prefixes error codes; `docs/api.md` documents errors.

## Approach

List each canonical error code and the condition that returns it.

## Acceptance

- `docs/api.md` lists each canonical API error code under the errors section.
EOF

# Target task: readiness-ready, but its Context carries an Obsidian wikilink
# `[[api_error-codes]]` that the task linter blocks. The conversion target is
# determinable (the sibling file above), so finalization converts it to a
# standard markdown link.
cat > "$target/proj/tasks/api_errors-ready.md" <<'EOF'
---
description: Document the API JSON error envelope so clients can parse error codes and messages consistently.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# API JSON error envelope docs

## Goal

Document the JSON error envelope returned by API endpoints so clients can parse the error code and human message from a single consistent shape.

## Context

`docs/api.md` documents public API response behavior. `src/api/errors.py` builds the error envelope. The catalog of codes lives in the [[api_error-codes]] task.

## Approach

Update the errors documentation in `docs/api.md` to describe the JSON error-envelope shape — the code, message, and request-id fields — emitted by `src/api/errors.py`.

## Acceptance

- `docs/api.md` documents the JSON error envelope under the errors section, naming the code, message, and request-id fields.
- Running `grep -nE 'error|code|request-id' docs/api.md` after the docs edit extracts the documented envelope fields, and running `grep -nE 'ERROR_CODE_PREFIX' src/api/errors.py` extracts the code prefix; both describe the same error shape.
EOF

commit_proj "$target"
