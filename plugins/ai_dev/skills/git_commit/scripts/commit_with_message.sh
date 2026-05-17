#!/usr/bin/env bash
# commit_with_message.sh — stage the repo and commit from an exact message file.

set -euo pipefail

case "${1:-}" in
  -h|--help|'')
    cat <<'USAGE'
commit_with_message.sh — stage the repo and commit from an exact message file.

Usage:
  commit_with_message.sh MESSAGE_FILE

Behavior:
  - Runs from any path inside a git repository.
  - Stages the full current repository state with git add -A.
  - Commits with git commit -F MESSAGE_FILE to preserve line breaks exactly.
  - Prints final git status after a successful commit.
USAGE
    [[ -z "${1:-}" ]] && exit 2 || exit 0
    ;;
esac

message_file="$1"

if [[ ! -f "$message_file" ]]; then
  echo "message file does not exist: $message_file" >&2
  exit 1
fi

if [[ ! -s "$message_file" ]]; then
  echo "message file is empty: $message_file" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git add -A
git commit -F "$message_file"
git status --short --untracked-files=all

# Clean up the context file written by prepare_commit_context.sh. Only runs
# on a successful commit (set -e exits the script earlier on any failure),
# so the context survives for a retry if the commit itself fails.
ctx_dir="${TMPDIR:-/tmp}"
ctx_dir="${ctx_dir%/}"
ctx_file="$ctx_dir/git_commit_context.txt"
[[ -f "$ctx_file" ]] && rm -f "$ctx_file"

exit 0
