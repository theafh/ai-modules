#!/usr/bin/env bash
# Shared helpers for guardrail_audit behavioral fixtures.
#
# Sandbox git is bound with explicit GIT_DIR + GIT_WORK_TREE. Never rely on
# bare `git -C <dir>` alone: when <dir> has no usable .git (failed init,
# sandbox blocked hooks/config), Git walks parent directories and can
# commit into the host checkout.

set -euo pipefail

# Absolute, physical path for stable comparisons.
_abs() { (cd "$1" && pwd -P); }

# sandbox_git <proj> <git-args...>
# Run git against the sandbox only. Requires <proj>/.git to already exist
# as a directory (call after new_project / ensure_sandbox_git).
sandbox_git() {
  local proj="$1"
  shift
  local git_dir="$proj/.git"
  if [[ ! -d "$git_dir" ]]; then
    echo "sandbox_git: missing $git_dir — refusing to run git (would walk parents)" >&2
    exit 1
  fi
  # GIT_DIR + GIT_WORK_TREE pin the repo; unset other git-dir overrides.
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
    GIT_DIR="$git_dir" GIT_WORK_TREE="$proj" \
    git "$@"
}

# ensure_sandbox_git <proj>
# Assert <proj> is its own git toplevel via the pinned env, not via discovery.
ensure_sandbox_git() {
  local proj="$1"
  local git_dir="$proj/.git"
  if [[ ! -d "$git_dir" ]]; then
    echo "ensure_sandbox_git: $proj has no .git directory" >&2
    exit 1
  fi
  local reported
  reported="$(sandbox_git "$proj" rev-parse --show-toplevel)"
  if [[ "$(_abs "$proj")" != "$(_abs "$reported")" ]]; then
    echo "ensure_sandbox_git: toplevel mismatch proj=$proj reported=$reported" >&2
    exit 1
  fi
  # Discovery without GIT_DIR must also resolve here, not to a parent.
  local discovered
  discovered="$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$discovered" || "$(_abs "$proj")" != "$(_abs "$discovered")" ]]; then
    echo "ensure_sandbox_git: git -C discovery escaped sandbox (discovered=${discovered:-<empty>})" >&2
    exit 1
  fi
}

# new_project <target> -> wipes <target>, creates <target>/proj as a git
# repo, prints absolute proj path. Aborts unless the sandbox is its own root.
new_project() {
  local target="$1"
  rm -rf "$target"
  mkdir -p "$target"
  local proj="$target/proj"
  mkdir -p "$proj"

  # Init by path (creates $proj/.git). Capture failure explicitly so a
  # partial/broken .git cannot be left for a later parent-walking call.
  if ! git init -q --initial-branch=main "$proj"; then
    echo "new_project: git init failed for $proj" >&2
    rm -rf "$proj/.git"
    exit 1
  fi
  if [[ ! -d "$proj/.git" ]]; then
    echo "new_project: git init produced no $proj/.git" >&2
    exit 1
  fi

  if ! sandbox_git "$proj" config user.email "evals@example.com"; then
    echo "new_project: cannot write sandbox git config (sandbox permissions?)" >&2
    rm -rf "$proj/.git"
    exit 1
  fi
  sandbox_git "$proj" config user.name "Evals"
  ensure_sandbox_git "$proj"
  _abs "$proj"
}

# record_tree_hashes <proj> <outfile> -> sha256 of every regular file under
# proj, excluding the sandbox .git directory (host-irrelevant; keeps the
# inventory stable and avoids hashing hooks the sandbox may not write).
record_tree_hashes() {
  local proj="$1" outfile="$2"
  (
    cd "$proj"
    if command -v sha256sum >/dev/null 2>&1; then
      find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 sha256sum
    else
      find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 shasum -a 256
    fi
  ) > "$outfile"
}

# git_commit_all <proj> <message> -> commit the sandbox tree only.
git_commit_all() {
  local proj="$1" msg="$2"
  ensure_sandbox_git "$proj"
  sandbox_git "$proj" add -A
  # Allow empty only if fixtures need a baseline; normal fixtures have files.
  sandbox_git "$proj" commit -q -m "$msg"
}
