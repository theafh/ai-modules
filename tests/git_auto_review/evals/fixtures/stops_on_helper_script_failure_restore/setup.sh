#!/usr/bin/env bash
# Fixture: the `run_restore.sh` signalling path of the helper-script class.
#
# The run prompt carries the `run_restore.sh` environment note Approach **Build
# the tests** settles for Acceptance 42(c): the restore step is already failed,
# the working tree must be left at the recorded post-failure baseline the note
# names, and no further working-tree write may follow. This fixture stages that
# baseline as `.post_failure.report.py` beside the repository, holding the
# report.py content that stands after the failed restore, and stages a ledger
# reproduction that fails on the un-fixed `report.py`, so the run really
# reaches a restore-and-retry before the note's failure applies.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  # The ledger reproduction the run inherits: it fails on the un-fixed
  # `report.py`, so the round's ledger check fails and the run reaches its one
  # restore-and-retry, where the note's `run_restore.sh` failure applies.
  cat > check_total.py <<'EOF'
from report import total

assert total([1, 2, 3]) == 6, "total must sum the items"
EOF
  git add check_total.py
  git commit --quiet -m "seed a ledger reproduction"
  git update-ref refs/remotes/origin/main HEAD
)
record_head "$target"
record_index "$target"

# The recorded post-failure working-tree baseline: the report.py content that
# stands immediately after the failed `run_restore.sh`. The note names this path
# and the run must leave the tree there, so the pre-run content IS that baseline
# and the failed restore changes nothing.
cp "$target/repo/report.py" "$target/.post_failure.report.py"
