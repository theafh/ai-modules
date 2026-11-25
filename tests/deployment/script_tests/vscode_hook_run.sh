#!/usr/bin/env bash
# Regression coverage for the VS Code Copilot hook route.
#
# The vscode deploy target ships the charter guardrail to Copilot as a
# Copilot-native hook config (vscode-hooks.json) and nothing else: a JSON hook
# config whose basename is not vscode-hooks* is skipped rather than copied into
# ~/.copilot/hooks, the shell script still lands beside it, the config's
# relative ./hooks/ command is rewritten to the target's hook directory, and
# the VS Code user settings switch the two Claude hook sources off. Uninstall
# restores the settings key's recorded prior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
# Invoke the deploy script on the stock bash the floor targets.
DEPLOY_BASH="/bin/bash"
HOOKS_SRC="${REPO_ROOT}/plugins/ai_dev/hooks"
VSCODE_HOOKS_SRC="${HOOKS_SRC}/vscode-hooks.json"
SCRATCH="$(mktemp -d)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  [[ "$got" == "$want" ]] || fail "$msg (got='$got' want='$want')"
}

cleanup() {
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

cd "$REPO_ROOT"

assert_file "$DEPLOY_SCRIPT"
assert_file "$VSCODE_HOOKS_SRC"

# The user settings file beside the prompts root, resolved the way the deploy
# script resolves it.
vscode_settings_file() {  # home
  case "$OSTYPE" in
    darwin*) printf '%s' "$1/Library/Application Support/Code/User/settings.json" ;;
    *) printf '%s' "$1/.config/Code/User/settings.json" ;;
  esac
}

# ---------------------------------------------------------------------------
# Item 3: the committed config is valid JSON in Copilot's schema — hook
# objects directly under PreToolUse, each carrying command, with no matcher
# group and no nested hooks array.
# ---------------------------------------------------------------------------
jq -e . "$VSCODE_HOOKS_SRC" >/dev/null || fail "vscode-hooks.json is not valid JSON"
assert_eq "$(jq -r '.hooks.PreToolUse | type' "$VSCODE_HOOKS_SRC")" "array" \
  "vscode-hooks.json must carry a PreToolUse array under hooks"
assert_eq "$(jq '[.hooks.PreToolUse[] | select(type != "object")] | length' "$VSCODE_HOOKS_SRC")" "0" \
  "every PreToolUse item must be a hook object"
assert_eq "$(jq '[.hooks.PreToolUse[] | select(has("matcher"))] | length' "$VSCODE_HOOKS_SRC")" "0" \
  "a Copilot hook object carries no matcher key"
assert_eq "$(jq '[.hooks.PreToolUse[] | select(has("hooks"))] | length' "$VSCODE_HOOKS_SRC")" "0" \
  "a Copilot hook object carries no nested hooks array"
assert_eq "$(jq '[.hooks.PreToolUse[] | select((.command | type) != "string")] | length' "$VSCODE_HOOKS_SRC")" "0" \
  "every PreToolUse hook object must carry a command string"

# ---------------------------------------------------------------------------
# Item 4, committed half: the repository keeps the command relative, so no
# machine-specific path is ever committed.
# ---------------------------------------------------------------------------
committed_command="$(jq -r '.hooks.PreToolUse[0].command' "$VSCODE_HOOKS_SRC")"
case "$committed_command" in
  ./hooks/*) ;;
  *) fail "committed vscode-hooks.json command must stay relative, got: $committed_command" ;;
esac

# ---------------------------------------------------------------------------
# Dry runs. A scratch home keeps the repo's own deploy log and the real
# ~/.copilot out of every scenario.
# ---------------------------------------------------------------------------
GLOBAL_HOME="${SCRATCH}/global-home"
GLOBAL_LOG="${SCRATCH}/global-deploy.log"
PROJECT_DIR="${SCRATCH}/project"
PROJECT_LOG="${SCRATCH}/project-deploy.log"
mkdir -p "$GLOBAL_HOME" "$PROJECT_DIR"
SETTINGS_FILE="$(vscode_settings_file "$GLOBAL_HOME")"

deploy_global() {
  HOME="$GLOBAL_HOME" DEPLOYED_ARTIFACTS_LOG="$GLOBAL_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target vscode "$@"
}

deploy_project() {
  HOME="$GLOBAL_HOME" DEPLOYED_ARTIFACTS_LOG="$PROJECT_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" \
    --type hook --target vscode "$@"
}

global_dry="$(deploy_global --dry-run)"

# ---------------------------------------------------------------------------
# Item 1: every discovered JSON hook config whose basename is not
# vscode-hooks* is reported as a skip, and none of them is copied. The set is
# found by selector at run time rather than frozen here.
# ---------------------------------------------------------------------------
foreign_count=0
for config in "$HOOKS_SRC"/*.json; do
  [[ -f "$config" ]] || continue
  base="$(basename "$config")"
  [[ "$base" == vscode-hooks* ]] && continue
  name="${base%.*}"
  foreign_count=$((foreign_count + 1))
  printf '%s\n' "$global_dry" | grep -Fq "[$name] not a VS Code Copilot hook config" ||
    fail "global dry run must skip [$name] as a non-Copilot hook config"
  if printf '%s\n' "$global_dry" | grep -F 'would-copy' | grep -Fq "/$base"; then
    fail "global dry run must not copy the foreign hook config $base"
  fi
done
[[ "$foreign_count" -gt 0 ]] ||
  fail "expected at least one foreign hook config to exercise the vscode filter"

# ---------------------------------------------------------------------------
# Item 2: the filter narrowed the JSON route without dropping the script.
# ---------------------------------------------------------------------------
printf '%s\n' "$global_dry" | grep -F 'would-copy' | grep -Fq "${GLOBAL_HOME}/.copilot/hooks/charter_guardrail.sh" ||
  fail "global dry run must still copy charter_guardrail.sh into the Copilot hook dir"
printf '%s\n' "$global_dry" | grep -F 'would-copy' | grep -Fq "${GLOBAL_HOME}/.copilot/hooks/vscode-hooks.json" ||
  fail "global dry run must copy vscode-hooks.json into the Copilot hook dir"

# ---------------------------------------------------------------------------
# Item 4, dry-run half: the global rewrite targets the Copilot hook directory.
# ---------------------------------------------------------------------------
printf '%s\n' "$global_dry" | grep -F 'would-rewrite' | grep -Fq -- "-> ${GLOBAL_HOME}/.copilot/hooks/" ||
  fail "global dry run must rewrite ./hooks/ commands to the global Copilot hook dir"

# ---------------------------------------------------------------------------
# Item 7, dry-run half: the settings switch is reported for the vscode target,
# which previously reported no settings write at all.
# ---------------------------------------------------------------------------
printf '%s\n' "$global_dry" | grep -F 'would-merge' | grep -Fq "${SETTINGS_FILE} <- .chat.hookFilesLocations entries" ||
  fail "global dry run must report the chat.hookFilesLocations merge"
printf '%s\n' "$global_dry" | grep -Fq '".claude/settings.json":false' ||
  fail "the reported merge must carry the workspace Claude settings path set to false"
printf '%s\n' "$global_dry" | grep -Fq '"~/.claude/settings.json":false' ||
  fail "the reported merge must carry the user Claude settings path set to false"

# ---------------------------------------------------------------------------
# Item 5: a project-dir run rewrites to the project-relative hook directory
# rather than the global absolute path, and leaves the user settings alone.
# ---------------------------------------------------------------------------
project_dry="$(deploy_project --dry-run)"
printf '%s\n' "$project_dry" | grep -F 'would-rewrite' | grep -Fq -- '-> .github/hooks/' ||
  fail "project-dir dry run must rewrite ./hooks/ commands to .github/hooks/"
if printf '%s\n' "$project_dry" | grep -F 'would-rewrite' | grep -Fq "$GLOBAL_HOME"; then
  fail "project-dir dry run must not rewrite to the global hook directory"
fi
printf '%s\n' "$project_dry" | grep -Fq 'chat.hookFilesLocations is a user-level switch' ||
  fail "project-dir dry run must report that the user settings switch is skipped"

# ---------------------------------------------------------------------------
# A real deploy into the scratch home. A foreign settings entry and an
# unrelated key are planted first, so the entry merge is proven to narrow to
# the two Claude paths (items 7 and 9).
# ---------------------------------------------------------------------------
mkdir -p "${SETTINGS_FILE%/*}"
printf '%s\n' '{"chat.hookFilesLocations":{"/foreign/entry":true},"editor.fontSize":13}' > "$SETTINGS_FILE"

deploy_global >/dev/null

assert_eq "$(jq -c '.["chat.hookFilesLocations"]' "$SETTINGS_FILE")" \
  '{"/foreign/entry":true,".claude/settings.json":false,"~/.claude/settings.json":false}' \
  "the deploy must add the two Claude paths and keep the foreign entry"
assert_eq "$(jq -c '.["editor.fontSize"]' "$SETTINGS_FILE")" "13" \
  "the deploy must leave every other settings key untouched"

# The deploy log records the map's prior value for uninstall.
assert_eq "$(awk -F'\t' '$1 ~ /settings\.json\[chat\.hookFilesLocations\]$/ {print $5}' "$GLOBAL_LOG")" \
  '{"/foreign/entry":true}' \
  "the deploy log must record the settings map's prior value"

# The deployed config carries the absolute Copilot hook path, and the foreign
# configs never reached the hook directory.
assert_eq "$(jq -r '.hooks.PreToolUse[0].command' "${GLOBAL_HOME}/.copilot/hooks/vscode-hooks.json")" \
  "${GLOBAL_HOME}/.copilot/hooks/charter_guardrail.sh" \
  "the deployed config must rewrite its command to the deployed script"
deployed_hooks="$(cd "${GLOBAL_HOME}/.copilot/hooks" && printf '%s\n' * | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "$deployed_hooks" "charter_guardrail.sh vscode-hooks.json " \
  "the Copilot hook dir must hold only the guard script and the native config"

# ---------------------------------------------------------------------------
# Item 10: the deployed command blocks a CHARTER.md mutation and lets an
# ordinary file through. The envelope is Copilot-shaped: snake_case, with
# tool_name, tool_input.file_path, and cwd inside a repository carrying
# CHARTER.md at its root.
# ---------------------------------------------------------------------------
GUARD_REPO="${SCRATCH}/guard-repo"
mkdir -p "$GUARD_REPO"
printf '%s\n' '# Charter' > "$GUARD_REPO/CHARTER.md"
git -C "$GUARD_REPO" init -q

envelope() {  # cwd file_path
  jq -cn --arg cwd "$1" --arg f "$2" \
    '{timestamp:"2026-01-01T00:00:00Z",cwd:$cwd,session_id:"session",hook_event_name:"PreToolUse",tool_name:"edit",tool_input:{file_path:$f}}'
}

deployed_command="${GLOBAL_HOME}/.copilot/hooks/charter_guardrail.sh"
guard_rc=0
printf '%s' "$(envelope "$GUARD_REPO" CHARTER.md)" | "$deployed_command" >/dev/null 2>&1 || guard_rc=$?
assert_eq "$guard_rc" "2" "a CHARTER.md mutation envelope must exit 2"

ordinary_rc=0
printf '%s' "$(envelope "$GUARD_REPO" notes.txt)" | "$deployed_command" >/dev/null 2>&1 || ordinary_rc=$?
assert_eq "$ordinary_rc" "0" "an ordinary file envelope must exit 0"

# ---------------------------------------------------------------------------
# Item 8: uninstall restores the captured prior value.
# ---------------------------------------------------------------------------
deploy_global --uninstall >/dev/null
assert_eq "$(jq -c '.["chat.hookFilesLocations"]' "$SETTINGS_FILE")" '{"/foreign/entry":true}' \
  "uninstall must restore the settings map's recorded prior"
assert_eq "$(jq -c '.["editor.fontSize"]' "$SETTINGS_FILE")" "13" \
  "uninstall must leave every other settings key untouched"

# ---------------------------------------------------------------------------
# Item 8, absent-prior half: a key the deploy created is removed outright on
# uninstall, and the settings file stays valid JSON.
# ---------------------------------------------------------------------------
ABSENT_HOME="${SCRATCH}/absent-home"
ABSENT_LOG="${SCRATCH}/absent-deploy.log"
mkdir -p "$ABSENT_HOME"
HOME="$ABSENT_HOME" DEPLOYED_ARTIFACTS_LOG="$ABSENT_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target vscode >/dev/null
ABSENT_SETTINGS="$(vscode_settings_file "$ABSENT_HOME")"
assert_eq "$(jq -c '.["chat.hookFilesLocations"]' "$ABSENT_SETTINGS")" \
  '{".claude/settings.json":false,"~/.claude/settings.json":false}' \
  "a deploy with no prior key must create the settings map"
assert_eq "$(awk -F'\t' '$1 ~ /settings\.json\[chat\.hookFilesLocations\]$/ {print $5}' "$ABSENT_LOG")" \
  "@absent" \
  "a first write must record the absent marker as the prior"

HOME="$ABSENT_HOME" DEPLOYED_ARTIFACTS_LOG="$ABSENT_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --global >/dev/null
assert_eq "$(jq -r 'has("chat.hookFilesLocations")' "$ABSENT_SETTINGS")" "false" \
  "uninstall must remove a key whose recorded prior was the absent marker"
jq -e . "$ABSENT_SETTINGS" >/dev/null || fail "the settings file must stay valid JSON after uninstall"

printf 'VS Code Copilot hook routing regression passed\n'
