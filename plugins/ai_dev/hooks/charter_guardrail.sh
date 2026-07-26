#!/bin/sh
set -u

# charter_guardrail
#
# Block any mutation of the repo-root CHARTER.md unless the operator is on a
# human-reviewed guardrail/charter-* branch. The guard runs as a PreToolUse
# hook on Anthropic Claude, OpenAI Codex, and Google Antigravity, and inspects
# the mutation surfaces each harness exposes, because a charter rewrite can
# arrive through any of them:
#
#   1. A direct file edit (Claude Edit/Write -> tool_input.file_path).
#   2. An apply_patch envelope (Codex -> tool_input.command patch markers).
#   3. An Antigravity file-writing tool, detected by scanning string values in
#      toolCall.args for any non-read tool whose argument schema is unpublished.
#   4. A shell command (Claude/Codex Bash tool -> tool_input.command;
#      Antigravity run_command -> toolCall.args.CommandLine) that redirects into,
#      moves, copies, removes, restores, or edits CHARTER.md in place
#      (code.claude.com/docs/en/hooks, developers.openai.com/codex/hooks,
#      antigravity.google/docs/hooks).
#
# The shell scan is a best-effort static reading of the command. A path built
# from a shell variable, or an in-place edit by an interpreter outside the
# known mutator set, is not caught here; that residual relies on the agents'
# read-and-respect contract with the charter. Read-only shell references (cat,
# grep, test -f, git show/log/diff) and Antigravity's documented read tools
# (view_file, grep_search) emit no candidate and are never blocked, so the
# every-session consumption that reads CHARTER.md keeps working. Other
# Antigravity tool names fail closed when they pass a CHARTER.md string, because
# their argument semantics are not documented. Antigravity's treatment of a
# stdout decision paired with a non-zero exit is undocumented; the two pre-JSON
# aborts emit both contracts so every harness receives a denial signal.

emit_antigravity_deny() {
  ead_reason=$1
  ead_escaped=$(printf '%s' "$ead_reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"decision":"deny","reason":"%s"}\n' "$ead_escaped"
}

block() {
  block_reason=$1
  if [ "${is_antigravity:-false}" = true ]; then
    emit_antigravity_deny "$block_reason"
    exit 0
  fi
  printf '%s\n' "$block_reason" >&2
  exit 2
}

abort_all_contracts() {
  abort_reason=$1
  printf '%s\n' "$abort_reason" >&2
  emit_antigravity_deny "$abort_reason"
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
  abort_all_contracts "charter_guardrail: jq is required to inspect hook input and protect CHARTER.md."
fi

if ! printf '%s' "$input_json" | jq -e . >/dev/null 2>&1; then
  abort_all_contracts "charter_guardrail: hook input was not valid JSON, so CHARTER.md protection could not run."
fi

is_antigravity=false
if printf '%s' "$input_json" | jq -e 'has("toolCall")' >/dev/null 2>&1; then
  is_antigravity=true
fi

if [ "$is_antigravity" = true ]; then
  cwd=$(printf '%s' "$input_json" | jq -r '.toolCall.args.Cwd // .workspacePaths[0] // empty')
else
  cwd=$(printf '%s' "$input_json" | jq -r '.cwd // empty')
fi
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  cwd=$(pwd -P)
else
  cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || cwd=$(pwd -P)
fi

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$cwd")
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || exit 0
charter_path=$repo_root/CHARTER.md

[ -f "$charter_path" ] || exit 0

if [ "$is_antigravity" = true ]; then
  tool_name=$(printf '%s' "$input_json" | jq -r '.toolCall.name // empty')
else
  tool_name=$(printf '%s' "$input_json" | jq -r '.tool_name // empty')
fi

paths_file=$(mktemp "${TMPDIR:-/tmp}/charter_guardrail.XXXXXX") ||
  block "charter_guardrail: could not create a temporary file for path inspection."
trap 'rm -f "$paths_file"' EXIT HUP INT TERM

if [ "$is_antigravity" = true ]; then
  case "$tool_name" in
    run_command|view_file|grep_search) ;;
    *)
      printf '%s' "$input_json" |
        jq -r '.toolCall.args // {} | to_entries[] | select(.value | type == "string") | .value' >> "$paths_file"
      ;;
  esac
else
  file_path=$(printf '%s' "$input_json" | jq -r '.tool_input.file_path // empty')
  if [ -n "$file_path" ]; then
    printf '%s\n' "$file_path" >> "$paths_file"
  fi
fi

if [ "$is_antigravity" = true ]; then
  command_text=$(printf '%s' "$input_json" | jq -r '.toolCall.args.CommandLine // empty')
else
  command_text=$(printf '%s' "$input_json" | jq -r '.tool_input.command // empty')
fi
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
