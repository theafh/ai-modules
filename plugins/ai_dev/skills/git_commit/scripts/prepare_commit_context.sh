#!/usr/bin/env bash
# prepare_commit_context.sh — emit one structured context blob for /git_commit.

set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
prepare_commit_context.sh — write one structured context blob for /git_commit.

Usage:
  prepare_commit_context.sh

Behavior:
  - Runs from any path inside a git repository.
  - Stages every untracked file so new files are visible in the staged diff.
  - Writes status, recent commits, and per-file staged/unstaged diffs to a
    fresh unique file under the system tmp dir (TMPDIR or /tmp) created
    via mktemp. Every run gets its own path so stale files from prior
    runs never collide and never block a fresh write.
  - Prints exactly two lines to stdout: the context file's absolute path,
    and a one-line consumption directive telling the consumer to Read the
    whole file. This keeps stdout small regardless of changeset size so
    no agent harness ever truncates or persists it separately. The
    consumer is expected to pass this path back to commit_with_message.sh
    so the file is cleaned up on a successful commit.
  - Prints generic placeholders for binary diffs.
  - Handles paths with embedded newlines, tabs, or other special characters
    by routing every path list through NUL-delimited git output.
  - Caches per-mode numstat once so per-file binary detection costs O(1)
    extra subprocesses instead of O(N).
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

# Stage every untracked, non-ignored file using NUL-delimited paths.
untracked_file_list="$tmp_dir/untracked-files"
git ls-files --others --exclude-standard -z > "$untracked_file_list"

if [[ -s "$untracked_file_list" ]]; then
  while IFS= read -r -d '' path; do
    git add -- "$path"
  done < "$untracked_file_list"
fi

# Cache numstat per mode in plain indexed arrays (bash 3.2 compatible).
# Each entry holds one numstat row: "<added>\t<deleted>\t<path>".
staged_numstat=()
unstaged_numstat=()

load_numstat() {
  local mode="$1"
  local entry
  local -a buffer=()

  if [[ "$mode" == "staged" ]]; then
    while IFS= read -r -d '' entry; do
      [[ -n "$entry" ]] && buffer+=("$entry")
    done < <(git diff --cached --numstat -z)
    staged_numstat=("${buffer[@]}")
  else
    while IFS= read -r -d '' entry; do
      [[ -n "$entry" ]] && buffer+=("$entry")
    done < <(git diff --numstat -z)
    unstaged_numstat=("${buffer[@]}")
  fi
}

load_numstat "staged"
load_numstat "unstaged"

is_binary_diff() {
  local mode="$1"
  local target_path="$2"
  local entry rest path added
  local -a entries

  if [[ "$mode" == "staged" ]]; then
    entries=("${staged_numstat[@]:-}")
  else
    entries=("${unstaged_numstat[@]:-}")
  fi

  for entry in "${entries[@]}"; do
    [[ -z "$entry" ]] && continue
    added="${entry%%$'\t'*}"
    rest="${entry#*$'\t'}"
    path="${rest#*$'\t'}"
    if [[ "$path" == "$target_path" ]]; then
      [[ "$added" == "-" ]]
      return $?
    fi
  done

  return 1
}

print_command_output() {
  local title="$1"
  shift

  printf '<%s>\n' "$title"
  "$@"
  printf '</%s>\n' "$title"
}

print_file_diff() {
  local mode="$1"
  local path="$2"

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

  if [[ "$mode" == "staged" ]]; then
    git diff --cached --name-only -z > "$path_list"
  else
    git diff --name-only -z > "$path_list"
  fi

  printf '<%s_file_diffs>\n' "$mode"
  if [[ -s "$path_list" ]]; then
    while IFS= read -r -d '' path; do
      print_file_diff "$mode" "$path"
    done < "$path_list"
  fi
  printf '</%s_file_diffs>\n' "$mode"
}

print_new_files() {
  local list="$tmp_dir/new-files"
  git diff --cached --name-only --diff-filter=A -z > "$list"

  printf '<staged_new_files>\n'
  if [[ -s "$list" ]]; then
    while IFS= read -r -d '' path; do
      printf '%s\n' "$path"
    done < "$list"
  fi
  printf '</staged_new_files>\n'
}

# Unique per-run path. mktemp -t respects TMPDIR on macOS and falls
# back to /tmp elsewhere. The trailing XXXXXX is the randomized suffix
# every mktemp implementation we target understands.
ctx_file="$(mktemp -t git_commit_context.XXXXXX)"

{
  printf '<commit_context>\n'
  printf '<repo_root>%s</repo_root>\n' "$repo_root"

  print_command_output "status_after_staging_new_files" \
    git status --short --untracked-files=all

  print_command_output "recent_commits" \
    git --no-pager log --oneline -8

  print_new_files

  print_file_loop "staged"
  print_file_loop "unstaged"

  printf '<commit_message_instruction>\n'
  printf "Write the commit message from this context. For multiple files, use one concise summary sentence followed by one line per changed file in the format \`file name -> concrete change\`.\n"
  printf '</commit_message_instruction>\n'
  printf '</commit_context>\n'
} > "$ctx_file"

# Stdout is intentionally tiny: the path on its own line so simple tools can
# pick it up, then a one-line consumption directive. The blob lives in the
# file above; do NOT inline it here, or agent harnesses with output-size
# limits will truncate or persist it and confuse downstream consumers.
printf '%s\n' "$ctx_file"
printf 'Read this entire file with the Read tool. Do NOT re-run git diff, git status, or git log — the per-file <file_change> sections inside are authoritative and need to be consumed whole to write a coherent message. If Read paginates, continue with offset/limit until every byte is covered. Only fall back to grep/awk/sed for files so large that paginated Read is impractical, and even then iterate sequentially over every <file_change> section rather than querying for a specific file.\n'
