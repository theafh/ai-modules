#!/usr/bin/env bash
# Regression coverage for the VS Code Copilot hook route.
#
# The vscode deploy target ships the charter guardrail to Copilot as a
# Copilot-native hook config (vscode-hooks.json) and nothing else: a JSON hook
# config whose basename is not vscode-hooks* is skipped rather than copied into
# ~/.copilot/hooks, the shell script still lands beside it, and the config's
# relative ./hooks/ command is rewritten to the target's hook directory. The
# hook route writes no VS Code settings key, because chat.hookFilesLocations
# configures the Local harness only and leaves the Copilot harness reading the
# repository .claude/settings.json files. The settings-map merge helper is kept
# for the sibling instructions route and is covered here directly, including
# the JSON-with-comments settings file VS Code's editor writes.
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

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
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
# Item 3: the committed config is valid JSON in Copilot's schema — a top-level
# version, hook objects directly under PreToolUse, each carrying command, with
# no matcher group and no nested hooks array.
# ---------------------------------------------------------------------------
jq -e . "$VSCODE_HOOKS_SRC" >/dev/null || fail "vscode-hooks.json is not valid JSON"
assert_eq "$(jq -r '.version' "$VSCODE_HOOKS_SRC")" "1" \
  "vscode-hooks.json must carry the documented version key"
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
# Item 7: the hook route writes no VS Code settings key. chat.hookFilesLocations
# configures the Local harness only; the Copilot harness keeps reading the
# repository .claude/settings.json files, so the switch would not close that
# route and is not written.
# ---------------------------------------------------------------------------
if printf '%s\n' "$global_dry" | grep -Fq 'chat.hookFilesLocations'; then
  fail "global dry run must not report a chat.hookFilesLocations merge"
fi
if printf '%s\n' "$global_dry" | grep -F 'would-merge' | grep -Fq "$SETTINGS_FILE"; then
  fail "global dry run must not write the VS Code user settings file"
fi

# ---------------------------------------------------------------------------
# Item 5: a project-dir run rewrites to the project-relative hook directory
# rather than the global absolute path, and writes no settings file.
# ---------------------------------------------------------------------------
project_dry="$(deploy_project --dry-run)"
printf '%s\n' "$project_dry" | grep -F 'would-rewrite' | grep -Fq -- '-> .github/hooks/' ||
  fail "project-dir dry run must rewrite ./hooks/ commands to .github/hooks/"
if printf '%s\n' "$project_dry" | grep -F 'would-rewrite' | grep -Fq "$GLOBAL_HOME"; then
  fail "project-dir dry run must not rewrite to the global hook directory"
fi
if printf '%s\n' "$project_dry" | grep -Fq 'would-merge'; then
  fail "project-dir dry run must not merge a settings key"
fi

# ---------------------------------------------------------------------------
# A real deploy into the scratch home. A settings file planted beforehand with
# a comment, a trailing comma, and an unrelated key must come through the run
# untouched: the hook route does not read or write it.
# ---------------------------------------------------------------------------
mkdir -p "${SETTINGS_FILE%/*}"
cat > "$SETTINGS_FILE" <<'JSONC'
{
  // The VS Code editor keeps this comment.
  "editor.fontSize": 13,
}
JSONC
settings_before="$(sha256_of "$SETTINGS_FILE")"

deploy_global >/dev/null

assert_eq "$(sha256_of "$SETTINGS_FILE")" "$settings_before" \
  "a hook deploy must leave the VS Code user settings file byte-identical"

# The deployed config carries the absolute Copilot hook path, and the foreign
# configs never reached the hook directory.
assert_eq "$(jq -r '.hooks.PreToolUse[0].command' "${GLOBAL_HOME}/.copilot/hooks/vscode-hooks.json")" \
  "${GLOBAL_HOME}/.copilot/hooks/charter_guardrail.sh" \
  "the deployed config must rewrite its command to the deployed script"
assert_eq "$(jq -r '.version' "${GLOBAL_HOME}/.copilot/hooks/vscode-hooks.json")" "1" \
  "the deployed config must keep the version key"
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
# Uninstall removes the native config and the script the deploy logged.
# ---------------------------------------------------------------------------
deploy_global --uninstall >/dev/null
[[ ! -e "${GLOBAL_HOME}/.copilot/hooks/vscode-hooks.json" ]] ||
  fail "uninstall must remove the deployed native hook config"
[[ ! -e "${GLOBAL_HOME}/.copilot/hooks/charter_guardrail.sh" ]] ||
  fail "uninstall must remove the deployed guard script"

# ---------------------------------------------------------------------------
# Items 8 and 9: the settings-map helper the sibling instructions route reuses,
# exercised directly because the hook route has no caller for it. It merges at
# entry grain, keeps every other entry and key, records the map's prior value,
# and tolerates the comments and trailing commas VS Code's editor preserves.
# ---------------------------------------------------------------------------
HELPER_HOME="${SCRATCH}/helper-home"
HELPER_LOG="${SCRATCH}/helper-deploy.log"
mkdir -p "$HELPER_HOME"
helper_settings="${HELPER_HOME}/settings.json"
helper_out="${HELPER_HOME}/merge.out"
: > "$HELPER_LOG"

# The assignments below configure the sourced deployment.sh; shellcheck cannot
# see their use through `source=/dev/null`, so the whole body is exempt.
# shellcheck disable=SC2034
helper_run() {
  (
    set -- --global
    DEPLOYMENT_SH_SKIP_MAIN=1
    # shellcheck source=/dev/null
    source "$DEPLOY_SCRIPT"
    DRY_RUN=false
    SUMMARY_DEPLOY_ACTIONS=0
    SUMMARY_UNINSTALL_ACTIONS=0
    DEPLOYED_ARTIFACTS_LOG="$HELPER_LOG"
    merge_settings_map_entries "$DEPLOYMENT_CONF" "$helper_settings" \
      "chat.instructionsFilesLocations" vscode style '{"~/.claude/rules": false}'
  )
}

cat > "$helper_settings" <<'JSONC'
{
  // VS Code keeps this comment, and the editor accepts the trailing comma.
  "editor.fontSize": 13,
  "docs.url": "https://example.com/a//b",
  "chat.instructionsFilesLocations": {
    "/foreign/entry": true,
  },
}
JSONC

helper_run >"$helper_out" 2>&1 ||
  fail "a settings file carrying comments and trailing commas must not fail the merge"

assert_eq "$(jq -c '.["chat.instructionsFilesLocations"]' "$helper_settings")" \
  '{"/foreign/entry":true,"~/.claude/rules":false}' \
  "the merge must add its own entry and keep the foreign entry"
assert_eq "$(jq -c '.["editor.fontSize"]' "$helper_settings")" "13" \
  "the merge must leave every other settings key untouched"
assert_eq "$(jq -r '.["docs.url"]' "$helper_settings")" "https://example.com/a//b" \
  "a // inside a string value must survive the comment strip"
if grep -Fq 'VS Code keeps this comment' "$helper_settings"; then
  fail "the rewritten settings file must be strict JSON, with comments dropped"
fi
grep -Fq 'normalize' "$helper_out" ||
  fail "a rewritten settings file must be reported, got: $(cat "$helper_out")"

# The deploy log records the map's prior value for uninstall.
assert_eq "$(awk -F'\t' '$1 ~ /settings\.json\[chat\.instructionsFilesLocations\]$/ {print $5}' "$HELPER_LOG")" \
  '{"/foreign/entry":true}' \
  "the merge must record the settings map's prior value"

# A file that is not JSON at all is left as it is and the run continues, so one
# unreadable settings file never aborts a deploy.
printf '%s\n' 'not json at all' > "$helper_settings"
broken_before="$(sha256_of "$helper_settings")"
helper_rc=0
helper_run >"$helper_out" 2>&1 || helper_rc=$?
assert_eq "$helper_rc" "0" "an unparseable settings file must not fail the run"
assert_eq "$(sha256_of "$helper_settings")" "$broken_before" \
  "an unparseable settings file must be left as it is"
grep -Fq 'not parseable JSON' "$helper_out" ||
  fail "an unparseable settings file must be reported as a skip, got: $(cat "$helper_out")"

# ---------------------------------------------------------------------------
# Items 8 and 9, uninstall half: restore_json_key and strip_json_key address a
# dotted top-level key, so the recorded map prior restores and an @absent prior
# removes the key.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034
helper_uninstall() {  # prior
  local prior="$1"
  (
    set -- --global
    DEPLOYMENT_SH_SKIP_MAIN=1
    # shellcheck source=/dev/null
    source "$DEPLOY_SCRIPT"
    DRY_RUN=false
    SUMMARY_UNINSTALL_ACTIONS=0
    DEPLOYED_ARTIFACTS_LOG="$HELPER_LOG"
    restore_json_key "$helper_settings" "chat.instructionsFilesLocations" "$prior"
  )
}

printf '%s\n' '{"editor.fontSize":13,"chat.instructionsFilesLocations":{"/foreign/entry":true,"~/.claude/rules":false}}' \
  > "$helper_settings"
helper_uninstall '{"/foreign/entry":true}' >/dev/null ||
  fail "restoring the recorded prior must succeed"
assert_eq "$(jq -c '.["chat.instructionsFilesLocations"]' "$helper_settings")" '{"/foreign/entry":true}' \
  "uninstall must restore the settings map's recorded prior"
assert_eq "$(jq -c '.["editor.fontSize"]' "$helper_settings")" "13" \
  "uninstall must leave every other settings key untouched"

helper_uninstall '@absent' >/dev/null ||
  fail "removing a key whose prior was absent must succeed"
assert_eq "$(jq -r 'has("chat.instructionsFilesLocations")' "$helper_settings")" "false" \
  "uninstall must remove a key whose recorded prior was the absent marker"
jq -e . "$helper_settings" >/dev/null || fail "the settings file must stay valid JSON after uninstall"

printf 'VS Code Copilot hook routing regression passed\n'
