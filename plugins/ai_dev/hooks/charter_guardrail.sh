#!/bin/sh
set -u

# charter_guardrail
#
# Block any mutation of the repo-root CHARTER.md unless the operator is on a
# human-reviewed guardrail/charter-* branch. The guard runs as a PreToolUse
# hook on both Anthropic Claude and OpenAI Codex and inspects three mutation
# surfaces, because a charter rewrite can arrive through any of them:
#
#   1. A direct file edit (Claude Edit/Write -> tool_input.file_path).
#   2. An apply_patch envelope (Codex -> tool_input.command patch markers).
#   3. A shell command (Claude/Codex Bash tool -> tool_input.command) that
#      redirects into, moves, copies, removes, restores, or edits CHARTER.md
#      in place. Both harnesses report the shell tool as tool_name "Bash" and
#      carry the command at tool_input.command (code.claude.com/docs/en/hooks,
#      developers.openai.com/codex/hooks).
#
# The shell scan is a best-effort static reading of the command. A path built
# from a shell variable, or an in-place edit by an interpreter outside the
# known mutator set, is not caught here; that residual relies on the agents'
# read-and-respect contract with the charter. Read-only references (cat, grep,
# test -f, git show/log/diff) emit no candidate and are never blocked, so the
# every-session consumption that reads CHARTER.md keeps working.

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Single quote, for embedding in the double-quoted ERE patterns below.
sq=\'

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

# has_mutating_verb COMMAND -> 0 when COMMAND runs a content- or
# location-changing operation on a file argument; 1 otherwise. Word boundaries
# keep substrings (warm, charm, edited) from matching, and read-only git
# subcommands (show, log, diff) stay outside the set.
has_mutating_verb() {
  hmv_cmd=$1
  if printf '%s' "$hmv_cmd" | grep -qE \
    "(^|[^[:alnum:]_.-])(tee|mv|cp|rm|ln|truncate|git[[:space:]]+(checkout|restore|rm|mv))([^[:alnum:]_.-]|$)"; then
    return 0
  fi
  # In-place editors only mutate with an -i / --in-place flag (sed -i, sed -ri,
  # sed -i.bak, perl -i). A bare sed/perl that prints to stdout is a read.
  if printf '%s' "$hmv_cmd" | grep -qE "(^|[^[:alnum:]_.-])(sed|perl)([^[:alnum:]_.-]|$)" &&
    printf '%s' "$hmv_cmd" | grep -qE "((^|[[:space:]])-[[:alpha:]]*i([^[:alnum:]]|$)|--in-place)"; then
    return 0
  fi
  return 1
}

# emit_charter_shell_targets COMMAND -> print, one per line, every path the
# shell COMMAND would write, move, copy, remove, or restore whose basename is
# CHARTER.md. The caller resolves each against the repo root, so only the root
# CHARTER.md is ever treated as protected.
emit_charter_shell_targets() {
  esst_cmd=$1

  # Redirection target (> / >>, covering a here-doc's leading `> CHARTER.md`).
  # A redirection is a write regardless of the surrounding command word.
  printf '%s' "$esst_cmd" |
    grep -oE ">>?[[:space:]]*[\"$sq]?[^[:space:]\"$sq<>|&;()]*CHARTER\.md" 2>/dev/null |
    sed -E "s/^>>?[[:space:]]*[\"$sq]?//"

  # A mutating command word plus a CHARTER.md path argument.
  if has_mutating_verb "$esst_cmd"; then
    printf '%s' "$esst_cmd" |
      grep -oE "[\"$sq]?[^[:space:]\"$sq<>|&;()]*CHARTER\.md" 2>/dev/null |
      sed -E "s/^[\"$sq]//"
  fi
}

input_json=$(cat)

# Fast path: a charter mutation we can statically detect names the file. When
# the raw hook input never mentions CHARTER.md, there is nothing to protect, so
# exit before any jq/git work. This keeps the guard nearly free on the vast
# majority of Bash calls it now sees and avoids bricking a jq-less machine on
# unrelated commands.
case "$input_json" in
  *CHARTER.md*) ;;
  *) exit 0 ;;
esac

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

tool_name=$(printf '%s' "$input_json" | jq -r '.tool_name // empty')

paths_file=$(mktemp "${TMPDIR:-/tmp}/charter_guardrail.XXXXXX") ||
  block "charter_guardrail: could not create a temporary file for path inspection."
trap 'rm -f "$paths_file"' EXIT HUP INT TERM

file_path=$(printf '%s' "$input_json" | jq -r '.tool_input.file_path // empty')
if [ -n "$file_path" ]; then
  printf '%s\n' "$file_path" >> "$paths_file"
fi

command_text=$(printf '%s' "$input_json" | jq -r '.tool_input.command // empty')
if [ -n "$command_text" ]; then
  # apply_patch envelope markers (Codex file edits).
  printf '%s\n' "$command_text" |
    sed -n \
      -e 's/^\*\*\* Add File: //p' \
      -e 's/^\*\*\* Update File: //p' \
      -e 's/^\*\*\* Delete File: //p' \
      -e 's/^\*\*\* Move to: //p' >> "$paths_file"

  # Shell mutations (Bash tool). Skip apply_patch envelopes so a diff body that
  # merely contains a redirection or mutator in unrelated code is not scanned.
  if [ "$tool_name" != "apply_patch" ]; then
    emit_charter_shell_targets "$command_text" >> "$paths_file"
  fi
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
