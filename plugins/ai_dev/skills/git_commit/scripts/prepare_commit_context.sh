#!/usr/bin/env bash
# prepare_commit_context.sh — emit one structured context blob for /git_commit.

set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
prepare_commit_context.sh — emit one structured context blob for /git_commit.

Usage:
  prepare_commit_context.sh

Behavior:
  - Runs from any path inside a git repository.
  - Stages every untracked file so new files are visible in the staged diff.
  - Prints status, recent commits, and per-file staged/unstaged diffs.
  - Prints generic placeholders for binary diffs.
USAGE
    exit 0
    ;;
  '')
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

untracked_file_list="$tmp_dir/untracked-files"
git ls-files --others --exclude-standard -z > "$untracked_file_list"

if [[ -s "$untracked_file_list" ]]; then
  while IFS= read -r -d '' path; do
    git add -- "$path"
  done < "$untracked_file_list"
fi

print_command_output() {
  local title="$1"
  shift

  printf '<%s>\n' "$title"
  "$@"
  printf '</%s>\n' "$title"
}

print_changed_paths() {
  local mode="$1"

  if [[ "$mode" == "staged" ]]; then
    git diff --cached --name-only
  else
    git diff --name-only
  fi
}

is_binary_diff() {
  local mode="$1"
  local path="$2"
  local numstat

  if [[ "$mode" == "staged" ]]; then
    numstat="$(git diff --cached --numstat -- "$path")"
  else
    numstat="$(git diff --numstat -- "$path")"
  fi

  [[ "$numstat" == -*$'\t'-* ]]
}

has_diff() {
  local mode="$1"
  local path="$2"

  if [[ "$mode" == "staged" ]]; then
    if git diff --cached --quiet -- "$path"; then
      return 1
    fi
  else
    if git diff --quiet -- "$path"; then
      return 1
    fi
  fi

  return 0
}

print_file_diff() {
  local mode="$1"
  local path="$2"

  has_diff "$mode" "$path" || return 0

  printf '<file_change mode="%s" path="%s">\n' "$mode" "$path"

  if is_binary_diff "$mode" "$path"; then
    printf '<binary_diff>Binary file changed; write a generic file-level commit line for this path.</binary_diff>\n'
  elif [[ "$mode" == "staged" ]]; then
    git --no-pager diff --no-ext-diff --cached -- "$path"
  else
    git --no-pager diff --no-ext-diff -- "$path"
  fi

  printf '</file_change>\n'
}

print_file_loop() {
  local mode="$1"
  local path_list="$tmp_dir/${mode}-paths"

  print_changed_paths "$mode" > "$path_list"

  printf '<%s_file_diffs>\n' "$mode"
  if [[ -s "$path_list" ]]; then
    while IFS= read -r path; do
      print_file_diff "$mode" "$path"
    done < "$path_list"
  fi
  printf '</%s_file_diffs>\n' "$mode"
}

printf '<commit_context>\n'
printf '<repo_root>%s</repo_root>\n' "$repo_root"

print_command_output "status_after_staging_new_files" \
  git status --short --untracked-files=all

print_command_output "recent_commits" \
  git --no-pager log --oneline -8

printf '<staged_new_files>\n'
git diff --cached --name-only --diff-filter=A
printf '</staged_new_files>\n'

print_file_loop "staged"
print_file_loop "unstaged"

printf '<commit_message_instruction>\n'
printf "Write the commit message from this context. For multiple files, use one concise summary sentence followed by one line per changed file in the format \`file name -> concrete change\`.\n"
printf '</commit_message_instruction>\n'
printf '</commit_context>\n'
