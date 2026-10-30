#!/usr/bin/env bash
# Fixture: the prompt names a branch other than the checked-out one.
#
# `main` is checked out and carries the stub remote shape `<orient>` needs, and
# a second `feature` branch exists so the prompt's `branch feature` phrase
# resolves to a real branch. Because that named target is not the checked-out
# branch, `<orient>` declines and names `git_checkout` as the skill that puts
# the repository on it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
  # A real branch beside the checked-out one, so the prompt's named target
  # resolves instead of falling through as a bare mention of the word.
  git branch feature
)
record_head "$target"
record_index "$target"

# The decline happens before any gate call, so this fixture stages no
# pre-seeded gate return: a preseed would create `.git_auto_review/default/`
# before the run and defeat the no-relay-directory proof.
