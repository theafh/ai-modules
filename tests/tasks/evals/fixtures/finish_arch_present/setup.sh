#!/usr/bin/env bash
# finish_arch_present fixture: a git-tracked backlog in a project that
# CARRIES an ARCHITECTURE.md, staging both sides of the close-out's
# design-signal decision so one fixture serves two evals.
#
#   api_pluggable-storage.md   design-extended: true
#       Replaced a hardwired SQLite dependency with a storage-backend
#       interface — a design decision ARCHITECTURE.md narrates, and one
#       the staged doc still describes the OLD way. Closing it must
#       refresh the doc and say what changed.
#
#   api_retry-after-header.md  design-extended: false
#       Added a response header. Behaviour-ledger material, not a
#       goals / stack / design-decision change. Closing it must decline
#       the refresh with a reason and leave ARCHITECTURE.md
#       byte-identical.
#
# Both tasks are staged `audited` so the close-out takes the
# trust-the-stamp path — the path that reads `design-extended` rather
# than re-reading the code. Everything is committed, so grade.sh can
# diff ARCHITECTURE.md against HEAD to prove edited-vs-byte-identical.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/ARCHITECTURE.md" <<'EOF'
# Architecture

## Goals

Serve the public API with predictable latency and a small operational
surface. Keep the deployment a single process with no external
coordination service.

## Stack

Python 3 with a hand-rolled WSGI layer. Persistence is SQLite, accessed
directly through the `sqlite3` module.

## Design decisions

- **Storage is SQLite, called directly.** Request handlers open the
  database through `sqlite3` themselves. There is no storage
  abstraction, and swapping the engine would mean editing every handler.
- **Fixed-window rate limiting in process.** Counters live in memory, so
  limits are per-process rather than per-cluster.
- **No background workers.** Everything a request needs happens inside
  the request.
EOF

cat > "$proj/tasks/api_pluggable-storage.md" <<EOF
---
description: replace the direct sqlite3 calls in every handler with one storage-backend interface so the engine can be swapped
scope: "api"
created: $now
updated: $now
status: audited
reported-by: Test User
implemented-by: Test User
design-extended: true
---

# Introduce a storage-backend interface

## Goal

Handlers talk to one \`StorageBackend\` interface instead of calling
\`sqlite3\` directly, so the persistence engine becomes a configuration
choice rather than something wired through every handler.

## Context

Every handler in \`src/api/handlers.py\` opens its own \`sqlite3\`
connection. That coupling is what makes the engine unswappable.

## Approach

Define the interface, port the handlers onto it, and select the concrete
backend from configuration at startup.

## Acceptance

- No handler imports \`sqlite3\` directly.
- The backend in use is chosen from configuration.
EOF

cat > "$proj/tasks/api_retry-after-header.md" <<EOF
---
description: send a Retry-After header on the 429 responses the rate limiter already returns
scope: "api"
created: $now
updated: $now
status: audited
reported-by: Test User
implemented-by: Test User
design-extended: false
---

# Send Retry-After on throttled responses

## Goal

A throttled client receives \`Retry-After\` alongside its HTTP 429, so it
knows how long to wait instead of guessing.

## Context

The rate limiter in \`src/api/throttle.py\` already computes the window
reset it needs for this; the value is simply not written to the response.

## Approach

Write the remaining window into the response header on the existing 429
path. The limiting behaviour itself stays as it is.

## Acceptance

- A throttled request's 429 response carries \`Retry-After\` in seconds.
EOF

git_commit_all "$proj" "seed: two audited tasks and an ARCHITECTURE.md describing SQLite-only storage"

echo "finish_arch_present sandbox staged at $proj"
