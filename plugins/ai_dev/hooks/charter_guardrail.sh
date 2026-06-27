#!/bin/sh
set -u

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

resolve_path() {
  rg_candidate=$1

  case "$rg_candidate" in
    /*) rg_full=$rg_candidate ;;
    *) rg_full=$cwd/$rg_candidate ;;
  esac

  rg_dir=$(dirname "$rg_full") || return 1
  rg_base=$(basename "$rg_full") || return 1

  [ -d "$rg_dir" ] || return 1
  (
    cd "$rg_dir" 2>/dev/null || exit 1
    printf '%s/%s\n' "$(pwd -P)" "$rg_base"
  )
}

input_json=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  block "charter_guardrail: jq is required to inspect hook input and protect CHARTER.md."
fi

if ! printf '%s' "$input_json" | jq -e . >/dev/null 2>&1; then
  block "charter_guardrail: hook input was not valid JSON, so CHARTER.md protection could not run."
fi

cwd=$(printf '%s' "$input_json" | jq -r '.cwd // empty')
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  cwd=$(pwd -P)
else
  cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || cwd=$(pwd -P)
fi

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$cwd")
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || exit 0
charter_path=$repo_root/CHARTER.md

[ -f "$charter_path" ] || exit 0

paths_file=$(mktemp "${TMPDIR:-/tmp}/charter_guardrail.XXXXXX") ||
  block "charter_guardrail: could not create a temporary file for path inspection."
trap 'rm -f "$paths_file"' EXIT HUP INT TERM

file_path=$(printf '%s' "$input_json" | jq -r '.tool_input.file_path // empty')
if [ -n "$file_path" ]; then
  printf '%s\n' "$file_path" >> "$paths_file"
fi

command_text=$(printf '%s' "$input_json" | jq -r '.tool_input.command // empty')
if [ -n "$command_text" ]; then
  printf '%s\n' "$command_text" |
    sed -n \
      -e 's/^\*\*\* Add File: //p' \
      -e 's/^\*\*\* Update File: //p' \
      -e 's/^\*\*\* Delete File: //p' \
      -e 's/^\*\*\* Move to: //p' >> "$paths_file"
fi

[ -s "$paths_file" ] || exit 0

is_charter_mutation=false
while IFS= read -r candidate_path || [ -n "$candidate_path" ]; do
  [ -n "$candidate_path" ] || continue
  resolved_path=$(resolve_path "$candidate_path" 2>/dev/null || printf '')
  if [ "$resolved_path" = "$charter_path" ]; then
    is_charter_mutation=true
    break
  fi
done < "$paths_file"

[ "$is_charter_mutation" = true ] || exit 0

branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '')
case "$branch" in
  guardrail/charter-*) exit 0 ;;
esac

block "CHARTER.md is protected. Switch to a guardrail/charter-* branch for human-reviewed charter changes."
