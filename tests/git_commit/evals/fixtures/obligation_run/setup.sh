#!/usr/bin/env bash
# Eval 9 fixture: an agent-directed obligation this commit does implicate.
#
# Mirror image of eval 8, and its control: the same scaffold plants a
# standing pre-commit rule, but the gate lints Markdown under docs/ and the
# working-tree change is a documentation edit under docs/. The subject
# matter the obligation governs and the paths this commit changes intersect,
# so git_commit's pre-flight relevance test must RUN the obligation, and it
# must run at the gate — before the commit lands.
#
# The gate is observable — tools/verify_docs.sh writes its epoch second to
# .eval/markers/verify_docs when it runs — and .eval/ is gitignored, so the
# marker never reaches git status or the commit.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
init_sandbox "$target"
target="$(cd "$target" && pwd)"

plant_obligation_scaffold "$target" verify_docs \
'Run `./tools/verify_docs.sh` before creating any commit. It lints every
Markdown file under `docs/` and fails while a lint error remains.'

# The change under review: a documentation edit, squarely inside the subject
# matter the docs gate governs.
(
    cd "$target"
    printf '\nThe handbook now documents the release steps.\n' >> docs/handbook.md
)

echo "Eval 9 sandbox staged at $target"
echo "  obligation: tools/verify_docs.sh (governs docs/) — expected RUN"
echo "  changed path: docs/handbook.md"
