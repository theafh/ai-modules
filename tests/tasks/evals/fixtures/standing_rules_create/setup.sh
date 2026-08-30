#!/usr/bin/env bash
# standing_rules_create fixture: root harness rule files only (CLAUDE.md
# and AGENTS.md), no family guardrail docs. The source note copies a
# repo rule verbatim; task_create must convert that copied rule into a
# citation to the standing repo rules in the task it writes.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

cat > "$proj/CLAUDE.md" <<'EOF'
# CLAUDE.md

## Repo Rules

Use Make plus POSIX shell for repo automation.
Keep package-manager setup out of automation tasks unless explicitly required.
EOF

cat > "$proj/AGENTS.md" <<'EOF'
# AGENTS.md

Follow the repo rules when task work touches automation, packaging, or build
entry points.
When a task needs a standing rule, cite it as the standing repo rules rather
than naming CLAUDE.md, AGENTS.md, or another harness-specific file.
EOF

mkdir -p "$proj/notes"
cat > "$proj/notes/packaging-smoke-test-draft.md" <<'EOF'
# Packaging smoke-test task draft

Goal: add a packaging smoke-test script for plugin manifest checks.

Context: Use Make plus POSIX shell for repo automation.

Approach: write a small shell entry point that exercises the packaging
manifest checks and keep it aligned with the repository automation setup.

Acceptance:

- The smoke-test command runs from the repository root.
- A malformed plugin manifest fixture causes the command to fail.
EOF

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
sha_of "$proj/notes/packaging-smoke-test-draft.md" > "$target/.source_sha256"

echo "standing_rules_create sandbox staged at $proj"
