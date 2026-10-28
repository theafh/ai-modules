#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
record_head "$target"
record_index "$target"
# `git worktree list --porcelain` emits a trailing blank line that command
# substitution strips, so write the snapshot with the same `printf '%s\n'`
# form the grader rebuilds; otherwise the grader's `cmp` is one `\n` short
# and reports DIFFERENT even on an unmodified fixture.
(cd "$target/repo" && git for-each-ref > "$target/.refs.before")
(cd "$target/repo" && printf '%s\n' "$(git worktree list --porcelain)" \
  > "$target/.worktrees.before")
