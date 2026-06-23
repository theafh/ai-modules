#!/usr/bin/env bash
# prepare_changelog_day.sh — write one structured context blob for /update_changelog,
# covering every commit authored on a single calendar day.

set -euo pipefail

usage() {
  cat <<'USAGE'
prepare_changelog_day.sh — write one structured context blob for /update_changelog.

Usage:
  prepare_changelog_day.sh YYYY-MM-DD

Behavior:
  - Runs from any path inside a git repository.
  - Selects every commit whose author date falls on the given calendar day
    (local time zone, midnight to midnight inclusive).
  - Writes commit subjects and bodies, the deduplicated repo-relative file list,
    and the day's net per-file diff (first-of-day commit's parent through
    last-of-day commit) to a fresh file under the system tmp dir, with a
    generic placeholder for binary diffs.
  - Prints exactly two lines to stdout: the context file's absolute path and a
    one-line consumption directive. The context file remains readable after the
    script exits.

Notes:
  - The day diff is the net change between the first selected commit's parent
    and the last selected commit. On a strictly linear history this matches the
    union of the day's commits exactly. On non-linear histories it includes any
    commits that landed in the same range, which is the human-readable "day
    state delta" most changelog summaries describe.
  - Exits 1 if the date has no commits, so the caller can skip silently.
USAGE
}

case "${1:-}" in
  -h|--help|'')
    usage
    [[ -z "${1:-}" ]] && exit 2 || exit 0
    ;;
esac

date_arg="$1"

if [[ ! "$date_arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "date must be YYYY-MM-DD: $date_arg" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

after="${date_arg}T00:00:00"
before="${date_arg}T23:59:59"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

hash_list="$tmp_dir/hashes"
git --no-pager log \
  --reverse \
  --no-merges \
  --after="$after" \
  --before="$before" \
  --format='%H' > "$hash_list"

if [[ ! -s "$hash_list" ]]; then
  echo "no commits on $date_arg" >&2
  exit 1
fi

first_hash="$(head -n1 "$hash_list")"
last_hash="$(tail -n1 "$hash_list")"

# Empty-tree hash is the well-known git constant used when the first commit of
# the day is the repository's root commit and therefore has no parent.
empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

if git rev-parse --verify --quiet "${first_hash}^" >/dev/null; then
  range="${first_hash}^..${last_hash}"
else
  range="${empty_tree}..${last_hash}"
fi

# Keep the returned context file outside tmp_dir: tmp_dir is trap-cleaned for
# internal lists, while the caller must still be able to read the context after
# this script exits. The full-template mktemp form works on BSD and GNU mktemp.
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
case "$tmp_root" in
  /*) ;;
  *) tmp_root="$(cd "$tmp_root" && pwd -P)" ;;
esac
ctx_file="$(mktemp "$tmp_root/update_changelog_day.${date_arg}.XXXXXX")"

is_binary_diff() {
  local path="$1"
  local numstat
  numstat="$(git diff --numstat "$range" -- "$path")"
  [[ "$numstat" == -*$'\t'-* ]]
}

print_commits() {
  printf '<commits>\n'
  while IFS= read -r hash; do
    local subject body
    subject="$(git --no-pager log -1 --format='%s' "$hash")"
    body="$(git --no-pager log -1 --format='%b' "$hash")"
    printf '<commit hash="%s">\n' "$hash"
    printf '<subject>%s</subject>\n' "$subject"
    if [[ -n "$body" ]]; then
      printf '<body>\n%s\n</body>\n' "$body"
    fi
    printf '</commit>\n'
  done < "$hash_list"
  printf '</commits>\n'
}

print_files_changed() {
  printf '<files_changed>\n'
  git diff --name-only "$range" | sort -u
  printf '</files_changed>\n'
}

print_diffs() {
  local path_list="$tmp_dir/paths"
  git diff --name-only "$range" | sort -u > "$path_list"

  printf '<diffs>\n'
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if is_binary_diff "$path"; then
      printf '<file_change path="%s" mode="binary">\n' "$path"
      printf '<binary_diff>Binary file changed; write a generic file-level summary for this path.</binary_diff>\n'
      printf '</file_change>\n'
    else
      printf '<file_change path="%s" mode="text">\n' "$path"
      git --no-pager diff --no-ext-diff "$range" -- "$path"
      printf '</file_change>\n'
    fi
  done < "$path_list"
  printf '</diffs>\n'
}

{
  printf '<changelog_day>\n'
  printf '<repo_root>%s</repo_root>\n' "$repo_root"
  printf '<date>%s</date>\n' "$date_arg"
  print_commits
  print_files_changed
  print_diffs
  cat <<EOF
<entry_instruction>
Compose one day section for ${date_arg}. Write a "## ${date_arg} — {Day theme}" heading, one bullet per logical change in the format "- **Category:** Plain-English summary.", and end the section with a "- **Files changed:** ..." bullet listing the paths from <files_changed> backtick-wrapped and comma-separated. Append the section to CHANGELOG.md immediately after the header so the file stays newest-first.
</entry_instruction>
</changelog_day>
EOF
} > "$ctx_file"

printf '%s\n' "$ctx_file"
printf 'Read this entire file with the Read tool. Treat the file as the authoritative per-day source: consume every <commit> and <file_change> in order, continue with offset/limit if Read paginates, and use ordered grep/awk/sed slices only when paginated Read is impractical. Do NOT re-run git log, git diff, or git status, and do NOT pipe the blob through head.\n'
