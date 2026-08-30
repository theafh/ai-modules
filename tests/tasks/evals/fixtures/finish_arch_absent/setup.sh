#!/usr/bin/env bash
# finish_arch_absent fixture: the presence gate. Same close-out, same
# task, but the project carries NO ARCHITECTURE.md.
#
# The staged task's `design-extended` is deliberately **true** — the
# signal that WOULD trigger a refresh. So the only thing that can stop
# one here is the doc's absence, which makes a pass unambiguous: had the
# task been staged `false`, a clean run would not tell us whether the
# presence gate held or the signal simply declined.
#
# The close-out must complete normally, create no ARCHITECTURE.md, and
# report the absent state.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

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

git_commit_all "$proj" "seed: one audited task with design-extended true and no ARCHITECTURE.md"

echo "finish_arch_absent sandbox staged at $proj"
