#!/usr/bin/env bash
# Fixture: the fixer's stray paths are caught and restored.
#
# Round 1 approves one in-scope bug in `report.py`. After the fixer returns its
# write, the run's orchestrator plants a stray untracked file in a new folder,
# an ignored text file in `__pycache__/`, and an ignored binary file there too.
# The round diff reports all three, the delta audit marks them unmapped, and
# the restore removes them together with the folders they created while the
# pre-existing ignored file `ignored/keep.txt` survives. Round 2 tags the
# finding closed so the retry stops clean.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
(
  cd "$target/repo"
  printf '__pycache__/\nignored/\n' > .gitignore
)
commit_repo "$target" "fixture base with ignores"
seed_in_scope_change "$target"
mkdir -p "$target/repo/ignored"
printf 'keep\n' > "$target/repo/ignored/keep.txt"
record_head "$target"
record_index "$target"

preseed_gate "$target" default 1 "$HERE/gate-r1.txt"
preseed_gate "$target" default 2 "$HERE/gate-r2.txt"
