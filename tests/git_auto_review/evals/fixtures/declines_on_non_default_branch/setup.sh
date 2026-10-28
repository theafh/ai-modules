#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  git checkout --quiet -b feature
)
record_head "$target"
record_index "$target"

# Acceptance 31 requires the run to create no run artefacts under Orient.'s
# decline move, so this fixture stages no pre-seeded gate return: a preseed
# would create `.git_auto_review/default/` before the run and defeat the
# absence proof.
