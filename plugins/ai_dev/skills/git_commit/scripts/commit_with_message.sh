#!/usr/bin/env bash
# commit_with_message.sh — stage the repo and commit from a message on stdin.

set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
commit_with_message.sh — stage the repo and commit from a message on stdin.

Usage:
  commit_with_message.sh [CONTEXT_FILE] < message
  printf 'subject\n\nbody' | commit_with_message.sh [CONTEXT_FILE]

Behavior:
  - Reads the commit message from stdin. Refuses an empty or
    whitespace-only message. Refuses to read from a TTY so an
    interactive invocation cannot hang forever waiting on input.
  - Runs from any path inside a git repository.
  - Stages the full current repository state with git add -A.
  - Commits with git commit -F - to preserve line breaks exactly.
  - Prints final git status after a successful commit.
  - If CONTEXT_FILE is provided (typically the path printed by
    prepare_commit_context.sh), removes it on a successful commit so
    each /git_commit run leaves no stale context behind. The context
    file is preserved if the commit fails so the next attempt can
    reuse it.
USAGE
    exit 0
    ;;
esac

context_file="${1:-}"

if [[ -t 0 ]]; then
  echo "no commit message on stdin (refusing to read from a TTY)" >&2
  echo "pipe the message in, e.g.:" >&2
  echo "  commit_with_message.sh CONTEXT_FILE <<'MSG_END'" >&2
  echo "  <commit message body>" >&2
  echo "  MSG_END" >&2
  exit 2
fi

message="$(cat)"

if [[ -z "${message//[[:space:]]/}" ]]; then
  echo "commit message on stdin is empty" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git add -A
printf '%s' "$message" | git commit -F -
git status --short --untracked-files=all

# Clean up the context file produced by prepare_commit_context.sh. Only
# runs on a successful commit (set -e exits the script earlier on any
# failure), so the context survives for a retry if the commit itself
# fails.
if [[ -n "$context_file" && -f "$context_file" ]]; then
  rm -f "$context_file"
fi

exit 0
