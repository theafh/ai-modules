#!/usr/bin/env bash
# commit_with_message.sh — stage the repo and commit from a message on stdin.

set -euo pipefail

usage() {
  cat <<'USAGE'
commit_with_message.sh — stage the repo and commit from a message on stdin.

Usage:
  commit_with_message.sh [CONTEXT_FILE] [--accept-drift] < message
  printf 'subject\n\nbody' | commit_with_message.sh [CONTEXT_FILE] [--accept-drift]

Behavior:
  - Reads the commit message from stdin. Refuses an empty or
    whitespace-only message (exit 1). Refuses to read from a TTY so an
    interactive invocation cannot hang forever waiting on input (exit 2).
  - Message-structure backstop: git reads line 1 as the subject and needs
    line 2 blank for the rest to parse as the body, so a message whose
    second line carries text is refused (exit 4). The refusal prints the
    problem to stderr, stages nothing, commits nothing, and leaves the
    CONTEXT_FILE in place for the retry. A one-line subject-only message
    and a message with a blank line 2 both pass, and a refusal never
    rewrites the message, so line breaks stay exact either way.
  - Runs from any path inside a git repository.
  - Foreign-drift backstop: when CONTEXT_FILE carries a
    <status_after_staging_new_files> baseline block, re-runs
    git status --short --untracked-files=all at commit time and compares
    path sets. When a path is present now that was absent from the
    reviewed baseline — the concurrent-session signal — refuses to commit
    (exit 3), prints the offending path(s) to stderr, and leaves the
    context file in place, staging nothing. Pass --accept-drift to record
    that the drift was reviewed and accepted, which commits the full tree
    anyway. With no CONTEXT_FILE, or a CONTEXT_FILE lacking the baseline
    block, there is no baseline to compare against, so the full tree is
    committed (the commit-all default, with no false drift block). The
    comparison is path-level: a concurrent edit to a path already in the
    baseline adds no new path and so commits without blocking, the same
    reach limit the model-side <detect_drift> check carries.
  - Stages the full current repository state with git add -A.
  - Commits with git commit -F - to preserve line breaks exactly.
  - Prints final git status after a successful commit.
  - If CONTEXT_FILE is provided (typically the path printed by
    prepare_commit_context.sh), removes it on a successful commit so
    each /git_commit run leaves no stale context behind. The context
    file is preserved if the commit fails or either refusal fires
    (drift, message structure) so the next attempt can reuse it.

Exit status:
  0  committed
  1  empty commit message on stdin
  2  refused to read the message from a TTY
  3  refused: foreign drift (paths outside the reviewed-set baseline)
  4  refused: message structure (line 2 carries text; git needs it blank)
USAGE
}

context_file=""
accept_drift=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --accept-drift)
      accept_drift=1
      shift
      ;;
    *)
      if [[ -z "$context_file" ]]; then
        context_file="$1"
        shift
      else
        echo "unexpected extra argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

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

# Message-structure backstop. Git reads line 1 as the subject and the rest as
# the body only when line 2 is blank; a body-bearing message that skips that
# blank line parses as one long subject, so git log --oneline, git shortlog,
# and git format-patch show the whole message as the title and the commit
# carries no body. Like the drift backstop below, this catches a model that
# composed past the skill's <message_policy> prose. Refusing rather than
# rewriting is what keeps the preserve-exact-line-breaks property intact. The
# check belongs with the stdin-message validations above and sits well ahead of
# git add -A, so a refusal stages nothing, commits nothing, and leaves
# CONTEXT_FILE in place. A whitespace-only line 2 passes: git's default
# --cleanup=whitespace strips it to empty, so the message still parses as
# subject plus body.
second_line="$(printf '%s\n' "$message" | sed -n '2p')"
if [[ -n "${second_line//[[:space:]]/}" ]]; then
  echo "commit message structure: line 2 must be blank so git reads line 1 as the subject and the rest as the body" >&2
  echo "line 2 was: $second_line" >&2
  echo "refusing to commit; recompose the message as a subject line, a blank line, then the body." >&2
  exit 4
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# Foreign-drift backstop. The model-side <detect_drift> protocol in SKILL.md is
# the first-line check that can pause and ask the user interactively; this block
# is the mechanical backstop that catches any model that skipped that prose
# step. It runs only with a real baseline to compare against: an accepted-drift
# override disables it, and an absent context file or one without the
# <status_after_staging_new_files> block leaves nothing to compare, so the
# commit-all default stands with no false block. The check sits ahead of
# git add -A so a refusal (exit 3) precedes both the commit and the context-file
# cleanup, preserving the persist-on-failure behavior.
if [[ "$accept_drift" -eq 0 && -n "$context_file" && -f "$context_file" ]] \
   && grep -q '^<status_after_staging_new_files>' "$context_file"; then
  # The reviewed-set baseline: the status snapshot prepare_commit_context.sh
  # captured right after staging untracked files. Compare paths, not status
  # codes — strip the 3-char short-status prefix (XY + space) from each line so
  # a concurrent same-path edit, which only shifts the code, does not read as
  # drift. A newly appeared path is what the guard is looking for.
  baseline_paths="$(
    awk '
      /^<\/status_after_staging_new_files>/ { inblk = 0 }
      inblk && length($0) >= 4 { print substr($0, 4) }
      /^<status_after_staging_new_files>/ { inblk = 1 }
    ' "$context_file"
  )"
  current_paths="$(
    git status --short --untracked-files=all \
      | awk 'length($0) >= 4 { print substr($0, 4) }'
  )"

  # Foreign paths: present now, absent from the reviewed baseline.
  foreign_paths=""
  while IFS= read -r current_path; do
    [[ -z "$current_path" ]] && continue
    if ! printf '%s\n' "$baseline_paths" | grep -qxF -- "$current_path"; then
      foreign_paths+="$current_path"$'\n'
    fi
  done <<< "$current_paths"

  if [[ -n "$foreign_paths" ]]; then
    echo "foreign drift: paths outside the reviewed-set baseline appeared at commit time:" >&2
    printf '%s' "$foreign_paths" >&2
    echo "refusing to commit; re-run with --accept-drift once these paths are confirmed to belong." >&2
    exit 3
  fi
fi

git add -A
printf '%s' "$message" | git commit -F -
git status --short --untracked-files=all

# Clean up the context file produced by prepare_commit_context.sh. Only runs on
# a successful commit (set -e exits the script earlier on any failure, and both
# refusals exit before this point: message structure with 4, drift with 3), so
# the context survives for a retry if the commit itself fails or a refusal fires.
if [[ -n "$context_file" && -f "$context_file" ]]; then
  rm -f "$context_file"
fi

exit 0
