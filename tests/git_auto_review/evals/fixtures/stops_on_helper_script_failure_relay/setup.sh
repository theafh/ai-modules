#!/usr/bin/env bash
# Fixture: the `run_relay.sh` signalling path of the helper-script class.
#
# The run prompt carries the `run_relay.sh` environment note Approach **Build
# the tests** settles, so the relay initialise step is already failed when the
# run starts. The failure lands before any working-tree write, so the tree must
# match its pre-run state and no relay directory may exist afterwards.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
record_head "$target"
record_index "$target"
(
  cd "$target/repo"
  cp report.py "$target/.report.before"
)
