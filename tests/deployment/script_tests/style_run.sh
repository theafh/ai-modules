#!/usr/bin/env bash
# Regression coverage for the style artefact type: Claude two-placement
# deploy, the output-style shadow report and global override caveat, Cursor
# project always-apply .mdc generation, Antigravity always-on rule generation
# at both scopes, and merge_json_key prior-value capture/restore.
set -euo pipefail

if [[ "${TEST_VENDOR:-}" == "cursor" ]] || [[ "${1:-}" == "--vendor" && "${2:-}" == "cursor" ]]; then
  printf '%s\n' \
    "style_run.sh is a deterministic script harness; --vendor is unsupported." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# Invoke the deploy script on the stock bash the floor targets.
DEPLOY_BASH="/bin/bash"
SCRATCH="$(mktemp -d)"
# Stage a throwaway repository root under $SCRATCH. deployment.sh walks up from
# its own directory to the first ancestor holding plugins/, so a staged copy
# beside a stub plugins/ and the styles/ tree resolves REPO_ROOT inside the
# sandbox. A --global run's "repo" context then reads the staged .claude
# settings, never this checkout's.
SANDBOX_ROOT="${SCRATCH}/repo"
mkdir -p "${SANDBOX_ROOT}/deployment" "${SANDBOX_ROOT}/plugins"
cp "${REPO_ROOT}/deployment/deployment.sh" "${SANDBOX_ROOT}/deployment/deployment.sh"
cp "${REPO_ROOT}/deployment/ai_asset_deploy.conf.template" "${SANDBOX_ROOT}/deployment/ai_asset_deploy.conf.template"
cp -R "${REPO_ROOT}/styles" "${SANDBOX_ROOT}/styles"
DEPLOY_SCRIPT="${SANDBOX_ROOT}/deployment/deployment.sh"
STYLE_SRC="${SANDBOX_ROOT}/styles/natural-language.md"
# Every deploy here writes a scratch log, never the machine-wide manifest.
DEPLOY_LOG="${SCRATCH}/deployed.log"
CONF_TEMPLATE="${SANDBOX_ROOT}/deployment/ai_asset_deploy.conf.template"

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

# This harness stages its own repository root, so a run must never write this
# checkout's .claude settings. Snapshot them here and assert at the end that
# the deploy's "repo" context read the staged sandbox instead.
repo_claude_snapshot() {
  local f
  for f in "${REPO_ROOT}/.claude/settings.local.json" "${REPO_ROOT}/.claude/settings.json"; do
    if [[ -f "$f" ]]; then
      cksum "$f"
    else
      printf 'absent %s\n' "$f"
    fi
  done
}
repo_claude_before="$(repo_claude_snapshot)"

cd "$REPO_ROOT"

# --- Static acceptance checks ---
assert_file "$STYLE_SRC"
grep -q 'keep-coding-instructions: true' "$STYLE_SRC" ||
  fail "style frontmatter missing keep-coding-instructions: true"

# Accepted Claude output-style frontmatter keys only
fm_keys="$(awk 'BEGIN{in_fm=0} /^---$/{in_fm++; next} in_fm==1{if(/^[a-zA-Z0-9_-]+:/){sub(/:.*/,"",$0); print}}' "$STYLE_SRC")"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  case "$key" in
    name|description|keep-coding-instructions|force-for-plugin) ;;
    *) fail "style frontmatter has non-accepted key: $key" ;;
  esac
done <<< "$fm_keys"

if grep -q "output-styles" plugins/*/.claude-plugin/plugin.json 2>/dev/null; then
  fail "plugin.json must not reference output-styles"
fi
plugin_count="$(grep -c "output-styles" plugins/*/.claude-plugin/plugin.json 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}' || true)"
[[ "$plugin_count" == "0" ]] || fail "grep -c output-styles on plugin.json should be 0 (got $plugin_count)"
output_style_dirs="$(find plugins -type d -name 'output-styles' 2>/dev/null || true)"
[[ -z "$output_style_dirs" ]] || fail "no plugin directory may contain output-styles/"

help_out="$("$DEPLOY_BASH" "$DEPLOY_SCRIPT" --help)"
printf '%s\n' "$help_out" | grep -q 'style' || fail "--help does not list style type"
grep -q 'STYLE_MAP\|style:<name>' "$DEPLOY_SCRIPT" || true
grep -q 'declare -a STYLE_MAP=()' "$DEPLOY_SCRIPT" ||
  fail "STYLE_MAP should be an indexed key|value table"
grep -n 'merge_json_key()' -A80 "$DEPLOY_SCRIPT" | grep -q 'lookup_logged_prior\|@absent' ||
  fail "first-write prior recording must live inside merge_json_key"

# --- Scratch trees ---
HOME_DIR="${SCRATCH}/home"
PROJECT_DIR="${SCRATCH}/project"
mkdir -p "$HOME_DIR" "$PROJECT_DIR"
# Pre-seed a home settings value that project-dir deploy must not touch
mkdir -p "$HOME_DIR/.claude"
printf '%s\n' '{"outputStyle":"home-prior"}' > "$HOME_DIR/.claude/settings.json"
# Seed the scratch home's per-tool config: the committed template plus the
# style this run deploys. The scratch HOME makes that file the config the
# script reads, so the style deploy still sets outputStyle without depending
# on the host's live config.
mkdir -p "$HOME_DIR/.ai_asset_deploy"
cp "$CONF_TEMPLATE" "$HOME_DIR/.ai_asset_deploy/config"
printf '\n#claude\nstyle:natural-language\n' >> "$HOME_DIR/.ai_asset_deploy/config"
export HOME="$HOME_DIR"
export DEPLOYED_ARTIFACTS_LOG="$DEPLOY_LOG"

# --- Global dry-run: two actions, resolved under scratch HOME ---
global_dry="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target claude --dry-run)"
printf '%s\n' "$global_dry" | grep -q "${HOME_DIR}/.claude/output-styles/natural-language.md" ||
  fail "global dry-run missing style file copy into user output-styles"
printf '%s\n' "$global_dry" | grep -q "${HOME_DIR}/.claude/settings.json" ||
  fail "global dry-run missing settings merge"
printf '%s\n' "$global_dry" | grep -q 'would-copy' || fail "global dry-run missing would-copy"
printf '%s\n' "$global_dry" | grep -q 'would-merge' || fail "global dry-run missing would-merge"
copy_count="$(printf '%s\n' "$global_dry" | grep -c 'would-copy.*output-styles/natural-language' || true)"
merge_count="$(printf '%s\n' "$global_dry" | grep -c 'would-merge.*settings.json' || true)"
[[ "$copy_count" -ge 1 && "$merge_count" -ge 1 ]] ||
  fail "global dry-run should report copy + merge for one style"

# --- Project dry-run: same two actions against project .claude, no home writes ---
project_dry="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --dry-run)"
printf '%s\n' "$project_dry" | grep -q "${PROJECT_DIR}/.claude/output-styles/natural-language.md" ||
  fail "project dry-run missing style file copy"
printf '%s\n' "$project_dry" | grep -q "${PROJECT_DIR}/.claude/settings.json" ||
  fail "project dry-run missing settings merge"
if printf '%s\n' "$project_dry" | grep -q "${HOME_DIR}/.claude/"; then
  fail "project dry-run must not resolve paths under HOME"
fi

# --- Cursor project dry-run: one .mdc write, nothing under home ---
cursor_project_dry="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target cursor --dry-run)"
printf '%s\n' "$cursor_project_dry" | grep -q "${PROJECT_DIR}/.cursor/rules/natural-language.mdc" ||
  fail "cursor project dry-run missing .mdc rule write"
printf '%s\n' "$cursor_project_dry" | grep -q 'would-gen' ||
  fail "cursor project dry-run missing would-gen"
mdc_count="$(printf '%s\n' "$cursor_project_dry" | grep -c 'would-gen.*\.cursor/rules/natural-language\.mdc' || true)"
assert_eq "$mdc_count" "1" "cursor project dry-run should report one .mdc write"
if printf '%s\n' "$cursor_project_dry" | grep -qE "${HOME_DIR}/(\.cursor/|plugins/)"; then
  fail "cursor project dry-run must not resolve paths under HOME"
fi

# --- Cursor global: report no injecting path, write nothing ---
mkdir -p "$HOME_DIR/.cursor/rules" "$HOME_DIR/.cursor/plugins/local"
printf '%s\n' 'pre-existing' > "$HOME_DIR/.cursor/rules/keep-me.mdc"
cursor_global="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target cursor --clear-backups)"
printf '%s\n' "$cursor_global" | grep -qi 'no deployable machine-wide rule-file path' ||
  fail "cursor global must report no deployable machine-wide rule-file path"
printf '%s\n' "$cursor_global" | grep -q 'Customize → Rules' ||
  fail "cursor global must name Customize → Rules paste"
[[ ! -e "$HOME_DIR/.cursor/rules/natural-language.mdc" ]] ||
  fail "cursor global must not write a style rule under user rules/"
plugin_mdc="$(find "$HOME_DIR/.cursor/plugins/local" -name '*.mdc' 2>/dev/null || true)"
[[ -z "$plugin_mdc" ]] || fail "cursor global must not install a style rule under plugins/local/"
assert_file "$HOME_DIR/.cursor/rules/keep-me.mdc"

# --- Real project-dir deploy ---
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
assert_file "$PROJECT_DIR/.claude/output-styles/natural-language.md"
cmp -s "$STYLE_SRC" "$PROJECT_DIR/.claude/output-styles/natural-language.md" ||
  fail "project deploy style file not byte-identical to repo source"
jq -e '.outputStyle == "natural-language"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "project deploy did not set outputStyle to conf style name"
jq -e '.outputStyle == "home-prior"' "$HOME_DIR/.claude/settings.json" >/dev/null ||
  fail "project deploy mutated home settings"

# --- Cursor real project-dir deploy ---
mkdir -p "$PROJECT_DIR/.cursor/rules"
sibling_rule="$PROJECT_DIR/.cursor/rules/keep-sibling.mdc"
sibling_saved="${SCRATCH}/keep-sibling.mdc"
printf '%s\n' '---' 'alwaysApply: true' '---' 'pre-existing sibling' > "$sibling_rule"
cp "$sibling_rule" "$sibling_saved"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target cursor >/dev/null
cursor_rule="$PROJECT_DIR/.cursor/rules/natural-language.mdc"
assert_file "$cursor_rule"
# Parses as Markdown with YAML frontmatter and alwaysApply: true
awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$cursor_rule" | grep -q 'alwaysApply: true' ||
  fail "cursor rule missing alwaysApply: true in frontmatter"
if grep -qE 'keep-coding-instructions|force-for-plugin' "$cursor_rule"; then
  fail "cursor rule must not carry Claude output-style frontmatter keys"
fi
if grep -qi 'keep-coding-instructions' "$cursor_rule"; then
  fail "cursor rule body must not reference keep-coding-instructions"
fi
eb_line="$(tr '\n' ' ' < "$cursor_rule" | grep -o '<engineering_behavior>[^<]*</engineering_behavior>' || true)"
[[ -n "$eb_line" ]] || fail "cursor rule missing <engineering_behavior>"
printf '%s\n' "$eb_line" | grep -qi 'named prose surfaces' ||
  fail "engineering_behavior must name prose surfaces"
printf '%s\n' "$eb_line" | grep -qi 'coding' ||
  fail "engineering_behavior must leave coding behaviour with Cursor"
printf '%s\n' "$eb_line" | grep -qi 'tool-use' ||
  fail "engineering_behavior must leave tool-use behaviour with Cursor"
printf '%s\n' "$eb_line" | grep -qi "Cursor's defaults" ||
  fail "engineering_behavior must name Cursor's defaults"
printf '%s\n' "$eb_line" | grep -qi 'append' ||
  fail "engineering_behavior must state harness only appends"
cmp -s "$sibling_saved" "$sibling_rule" ||
  fail "cursor deploy changed pre-existing sibling rule"

# --- Redeploy: single log entry per artefact, same settings value ---
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
file_log_count="$(grep -cF "${PROJECT_DIR}/.claude/output-styles/natural-language.md"$'\t' "$DEPLOY_LOG" || true)"
key_log_count="$(grep -cF "${PROJECT_DIR}/.claude/settings.json[outputStyle]"$'\t' "$DEPLOY_LOG" || true)"
assert_eq "$file_log_count" "1" "expected one log line for style file after redeploy"
assert_eq "$key_log_count" "1" "expected one log line for outputStyle after redeploy"
jq -e '.outputStyle == "natural-language"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "redeploy changed outputStyle"

# --- Cursor uninstall removes deployed rule, leaves sibling ---
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target cursor --uninstall >/dev/null
[[ ! -e "$cursor_rule" ]] || fail "cursor uninstall left deployed rule"
cmp -s "$sibling_saved" "$sibling_rule" ||
  fail "cursor uninstall changed pre-existing sibling rule"

# --- Project uninstall restores @absent (no prior key) ---
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --uninstall >/dev/null
[[ ! -e "$PROJECT_DIR/.claude/output-styles/natural-language.md" ]] ||
  fail "uninstall left style file"
if jq -e 'has("outputStyle")' "$PROJECT_DIR/.claude/settings.json" >/dev/null 2>&1; then
  fail "uninstall left outputStyle present when prior was absent"
fi
if grep -qF "${PROJECT_DIR}/.claude/settings.json[outputStyle]" "$DEPLOY_LOG" 2>/dev/null; then
  fail "uninstall left settings path[key] log line"
fi
jq -e '.outputStyle == "home-prior"' "$HOME_DIR/.claude/settings.json" >/dev/null ||
  fail "project uninstall mutated home settings"

# --- Prior restore: existing non-deployed value survives deploy+uninstall ---
mkdir -p "$PROJECT_DIR/.claude"
printf '%s\n' '{"outputStyle":"Explanatory","other":1}' > "$PROJECT_DIR/.claude/settings.json"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
jq -e '.outputStyle == "natural-language"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "deploy with prior did not set natural-language"
# Second deploy must keep first prior (Explanatory), not the live natural-language
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
prior_field="$(awk -F'\t' -v p="${PROJECT_DIR}/.claude/settings.json[outputStyle]" '$1==p{print $5; exit}' "$DEPLOY_LOG")"
assert_eq "$prior_field" '"Explanatory"' "first-write prior must stay Explanatory across redeploy"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --uninstall >/dev/null
jq -e '.outputStyle == "Explanatory"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "uninstall did not restore original Explanatory prior"
if grep -qF "${PROJECT_DIR}/.claude/settings.json[outputStyle]" "$DEPLOY_LOG" 2>/dev/null; then
  fail "uninstall left settings path[key] after prior restore"
fi

# --- Single-deploy then uninstall restores prior (scalar path) ---
printf '%s\n' '{"outputStyle":"Learning"}' > "$PROJECT_DIR/.claude/settings.json"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --uninstall >/dev/null
jq -e '.outputStyle == "Learning"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "uninstall did not restore Learning prior"

# --- Global real deploy into scratch HOME ---
rm -f "$DEPLOY_LOG"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target claude --clear-backups >/dev/null
assert_file "$HOME_DIR/.claude/output-styles/natural-language.md"
cmp -s "$STYLE_SRC" "$HOME_DIR/.claude/output-styles/natural-language.md" ||
  fail "global deploy style file not byte-identical"
jq -e '.outputStyle == "natural-language"' "$HOME_DIR/.claude/settings.json" >/dev/null ||
  fail "global deploy did not set outputStyle"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target claude --uninstall >/dev/null

# --- Legacy four-field path[key] still strips ---
rm -f "$DEPLOY_LOG"
legacy_settings="${SCRATCH}/legacy-settings.json"
printf '%s\n' '{"outputStyle":"keep-me","hooks":{}}' > "$legacy_settings"
printf '%s\t%s\t%s\t%s\n' \
  "${legacy_settings}[outputStyle]" "claude" "style" "styles/natural-language.md" \
  > "$DEPLOY_LOG"
dry_legacy="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --type style --target claude --dry-run)"
printf '%s\n' "$dry_legacy" | grep -q 'would-strip' ||
  fail "legacy four-field dry-run should report strip without fifth field"
# Restore log for real uninstall (dry-run keeps entries)
printf '%s\t%s\t%s\t%s\n' \
  "${legacy_settings}[outputStyle]" "claude" "style" "styles/natural-language.md" \
  > "$DEPLOY_LOG"
HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --type style --target claude >/dev/null
if jq -e 'has("outputStyle")' "$legacy_settings" >/dev/null 2>&1; then
  fail "legacy four-field uninstall should strip the key"
fi
jq -e 'has("hooks")' "$legacy_settings" >/dev/null ||
  fail "legacy strip removed unrelated keys"

# --- Direct merge_json_key nested object/array prior round-trip ---
rm -f "$DEPLOY_LOG"
nested_target="${SCRATCH}/nested-settings.json"
nested_source="${SCRATCH}/nested-patch.json"
printf '%s\n' '{"customBlock":{"a":1,"b":[2,3]},"keep":true}' > "$nested_target"
printf '%s\n' '{"customBlock":{"replaced":true}}' > "$nested_source"
original_block="$(jq -c '.customBlock' "$nested_target")"

# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$DEPLOY_LOG"
  merge_json_key "$nested_source" "$nested_target" "customBlock" "claude" "hook"
)

jq -e '.customBlock.replaced == true' "$nested_target" >/dev/null ||
  fail "direct merge_json_key did not write replacement"
logged_prior="$(awk -F'\t' -v p="${nested_target}[customBlock]" '$1==p{print $5; exit}' "$DEPLOY_LOG")"
assert_eq "$logged_prior" "$original_block" "nested prior not recorded as compact JSON"

# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall --type hook --target claude
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$DEPLOY_LOG"
  TYPE_FILTER="hook"
  TARGET_FILTER="claude"
  uninstall_logged_artifacts
)

restored_block="$(jq -c '.customBlock' "$nested_target")"
assert_eq "$restored_block" "$original_block" "nested object/array prior did not round-trip"
jq -e '.keep == true' "$nested_target" >/dev/null ||
  fail "nested restore clobbered unrelated keys"

# parse_deployment_conf recognizes style: via STYLE_MAP. The block runs under
# its own scratch home, seeded with a distinct style name, so it proves the
# script reads the seeded config rather than the host's live one.
# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  PARSE_HOME="${SCRATCH}/parse-home"
  mkdir -p "$PARSE_HOME/.ai_asset_deploy"
  cp "$CONF_TEMPLATE" "$PARSE_HOME/.ai_asset_deploy/config"
  printf '\n#claude\nstyle:scratch-only\n' >> "$PARSE_HOME/.ai_asset_deploy/config"
  HOME="$PARSE_HOME"
  export HOME
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  parse_deployment_conf
  style_for_claude="$(table_get "claude" "${STYLE_MAP[@]}")" ||
    fail "table_get on STYLE_MAP should yield the seeded style for claude"
  [[ "$style_for_claude" == "scratch-only" ]] ||
    fail "table_get on STYLE_MAP should yield the seeded style for claude"
)

# --- Antigravity: one generated always-on rule per scope ---
AG_LOG="${SCRATCH}/antigravity.log"
rm -f "$AG_LOG"
AG_RULES_DIR="${HOME_DIR}/.gemini/config/rules"

# Global dry-run: one rule write, no other artefact write, nothing on disk.
ag_global_dry="$(HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target antigravity --dry-run)"
printf '%s\n' "$ag_global_dry" | grep -q "${AG_RULES_DIR}/natural-language.md" ||
  fail "antigravity global dry-run missing rule write"
ag_gen_count="$(printf '%s\n' "$ag_global_dry" | grep -c 'would-gen' || true)"
assert_eq "$ag_gen_count" "1" "antigravity global dry-run should report one generated rule"
if printf '%s\n' "$ag_global_dry" | grep -qE 'would-(copy|merge|restore|strip)'; then
  fail "antigravity global dry-run must report no other artefact write"
fi
[[ ! -e "${HOME_DIR}/.gemini" ]] ||
  fail "antigravity global dry-run wrote under HOME"

# Project dry-run: one rule write in the workspace tree, nothing under HOME.
ag_project_dry="$(HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target antigravity --dry-run)"
printf '%s\n' "$ag_project_dry" | grep -q "${PROJECT_DIR}/.agents/rules/natural-language.md" ||
  fail "antigravity project dry-run missing rule write"
ag_project_gen="$(printf '%s\n' "$ag_project_dry" | grep -c 'would-gen' || true)"
assert_eq "$ag_project_gen" "1" "antigravity project dry-run should report one generated rule"
if printf '%s\n' "$ag_project_dry" | grep -vE '^(Config|Deploy log|Config source):' | grep -q "${HOME_DIR}/"; then
  fail "antigravity project dry-run must not resolve paths under HOME"
fi

# Seed the scratch global rules dir and the four standalone rule files: three
# present, one absent, so the deploy must leave every one exactly as it was.
mkdir -p "$AG_RULES_DIR" "${HOME_DIR}/.gemini/config"
ag_user_rule="${AG_RULES_DIR}/user-note.md"
printf '%s\n' '---' 'trigger: manual' '---' 'user rule body' > "$ag_user_rule"
ag_user_saved="${SCRATCH}/ag-user-note.md"
cp "$ag_user_rule" "$ag_user_saved"
ag_tree_agents="${HOME_DIR}/.gemini/AGENTS.md"
ag_tree_gemini="${HOME_DIR}/.gemini/GEMINI.md"
ag_config_agents="${HOME_DIR}/.gemini/config/AGENTS.md"
printf '%s\n' 'standalone tree AGENTS' > "$ag_tree_agents"
printf '%s\n' 'standalone tree GEMINI' > "$ag_tree_gemini"
printf '%s\n' 'standalone config AGENTS' > "$ag_config_agents"
ag_tree_agents_saved="${SCRATCH}/ag-tree-AGENTS.md"
ag_tree_gemini_saved="${SCRATCH}/ag-tree-GEMINI.md"
ag_config_agents_saved="${SCRATCH}/ag-config-AGENTS.md"
cp "$ag_tree_agents" "$ag_tree_agents_saved"
cp "$ag_tree_gemini" "$ag_tree_gemini_saved"
cp "$ag_config_agents" "$ag_config_agents_saved"

# Real global deploy adds one style file and touches nothing the user owns.
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target antigravity >/dev/null
ag_rule="${AG_RULES_DIR}/natural-language.md"
assert_file "$ag_rule"
awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$ag_rule" | grep -q 'trigger: always_on' ||
  fail "antigravity rule missing trigger: always_on in frontmatter"
if grep -qE 'keep-coding-instructions|force-for-plugin' "$ag_rule"; then
  fail "antigravity rule must not carry Claude output-style frontmatter keys"
fi
if grep -qi 'keep-coding-instructions' "$ag_rule"; then
  fail "antigravity rule body must not reference keep-coding-instructions"
fi
ag_eb="$(tr '\n' ' ' < "$ag_rule" | grep -o '<engineering_behavior>[^<]*</engineering_behavior>' || true)"
[[ -n "$ag_eb" ]] || fail "antigravity rule missing <engineering_behavior>"
printf '%s\n' "$ag_eb" | grep -qi 'named prose surfaces' ||
  fail "antigravity engineering_behavior must name prose surfaces"
printf '%s\n' "$ag_eb" | grep -qi "Antigravity's defaults" ||
  fail "antigravity engineering_behavior must name Antigravity's defaults"
printf '%s\n' "$ag_eb" | grep -qi 'append' ||
  fail "antigravity engineering_behavior must state harness only appends"
cmp -s "$ag_user_saved" "$ag_user_rule" ||
  fail "antigravity deploy changed a pre-existing user rule"
cmp -s "$ag_tree_agents_saved" "$ag_tree_agents" ||
  fail "antigravity deploy changed ~/.gemini/AGENTS.md"
cmp -s "$ag_tree_gemini_saved" "$ag_tree_gemini" ||
  fail "antigravity deploy changed ~/.gemini/GEMINI.md"
cmp -s "$ag_config_agents_saved" "$ag_config_agents" ||
  fail "antigravity deploy changed ~/.gemini/config/AGENTS.md"
[[ ! -e "${HOME_DIR}/.gemini/config/GEMINI.md" ]] ||
  fail "antigravity deploy created an absent standalone ~/.gemini/config/GEMINI.md"

# Redeploy leaves exactly one style rule and one log line.
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target antigravity >/dev/null
ag_rule_count="$(find "$AG_RULES_DIR" -maxdepth 1 -name 'natural-language.md' | wc -l | tr -d '[:space:]')"
assert_eq "$ag_rule_count" "1" "antigravity redeploy should leave exactly one style rule"
ag_log_count="$(grep -cF "${ag_rule}"$'\t' "$AG_LOG" || true)"
assert_eq "$ag_log_count" "1" "antigravity redeploy should leave one log line"

# Uninstall removes the style rule and restores the surrounding user content.
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --global --type style --target antigravity >/dev/null
[[ ! -e "$ag_rule" ]] || fail "antigravity uninstall left the deployed rule"
cmp -s "$ag_user_saved" "$ag_user_rule" ||
  fail "antigravity uninstall changed a pre-existing user rule"
cmp -s "$ag_tree_agents_saved" "$ag_tree_agents" ||
  fail "antigravity uninstall changed ~/.gemini/AGENTS.md"
cmp -s "$ag_tree_gemini_saved" "$ag_tree_gemini" ||
  fail "antigravity uninstall changed ~/.gemini/GEMINI.md"
cmp -s "$ag_config_agents_saved" "$ag_config_agents" ||
  fail "antigravity uninstall changed ~/.gemini/config/AGENTS.md"
[[ ! -e "${HOME_DIR}/.gemini/config/GEMINI.md" ]] ||
  fail "antigravity uninstall created an absent standalone ~/.gemini/config/GEMINI.md"

# Real project deploy writes the workspace rule; uninstall removes it outright.
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target antigravity >/dev/null
ag_project_rule="${PROJECT_DIR}/.agents/rules/natural-language.md"
assert_file "$ag_project_rule"
awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$ag_project_rule" | grep -q 'trigger: always_on' ||
  fail "antigravity project rule missing trigger: always_on in frontmatter"
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$AG_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --project-dir "$PROJECT_DIR" --type style --target antigravity >/dev/null
[[ ! -e "$ag_project_rule" ]] || fail "antigravity project uninstall left the deployed rule"

# Generated content over the 24,000-byte cap fails and writes nothing.
oversize_src="${SCRATCH}/oversize-style.md"
{
  printf '%s\n' '---' 'name: oversize' 'description: "Oversized fixture"' 'keep-coding-instructions: true' '---'
  printf '%s\n' '<engineering_behavior>original</engineering_behavior>'
  head -c 25000 /dev/zero | tr '\0' 'x'
  printf '\n'
} > "$oversize_src"
oversize_dest="${SCRATCH}/oversize-rules/oversize.md"
mkdir -p "$(dirname "$oversize_dest")"
# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
if (
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$AG_LOG"
  generate_antigravity_style_rule "$oversize_src" "$oversize_dest" "antigravity" "style"
) > "${SCRATCH}/oversize.out" 2>&1; then
  fail "oversized antigravity rule should fail"
fi
grep -qE '[0-9]{5} bytes' "${SCRATCH}/oversize.out" ||
  fail "oversized antigravity rule must name the actual size"
grep -q '24000-byte per-file cap' "${SCRATCH}/oversize.out" ||
  fail "oversized antigravity rule must name the limit"
[[ ! -e "$oversize_dest" ]] || fail "oversized antigravity rule must write nothing"

# --- VS Code Copilot: generated instructions file at both scopes ---
# The global run writes Copilot's own user-profile instructions root and merges
# the editor-forwarding settings key; the project run writes the project
# instructions directory and no settings key. Neither writes into the Claude
# configuration tree.
VS_LOG="${SCRATCH}/vscode.log"
rm -f "$VS_LOG"
VS_GLOBAL_FILE="${HOME_DIR}/.copilot/instructions/natural-language.instructions.md"
VS_PROJECT_FILE="${PROJECT_DIR}/.github/instructions/natural-language.instructions.md"
# The user settings file beside the prompts root, resolved the way the deploy
# script resolves it.
vscode_settings_file() {  # home
  case "$OSTYPE" in
    darwin*) printf '%s' "$1/Library/Application Support/Code/User/settings.json" ;;
    *) printf '%s' "$1/.config/Code/User/settings.json" ;;
  esac
}
VS_SETTINGS_FILE="$(vscode_settings_file "$HOME_DIR")"

vs_global_dry="$(HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target vscode --dry-run)"
vs_gen_count="$(printf '%s\n' "$vs_global_dry" | grep -c 'would-gen' || true)"
assert_eq "$vs_gen_count" "1" "vscode global dry-run should report exactly one generated style file"
printf '%s\n' "$vs_global_dry" | grep -q "$VS_GLOBAL_FILE" ||
  fail "vscode global dry-run missing the user-profile instructions write"
if printf '%s\n' "$vs_global_dry" | grep -q "${HOME_DIR}/.claude/"; then
  fail "vscode global dry-run must not write into the Claude configuration tree"
fi
printf '%s\n' "$vs_global_dry" | grep -q 'would-merge' ||
  fail "vscode global dry-run missing the settings-map merge"
printf '%s\n' "$vs_global_dry" | grep -q "$VS_SETTINGS_FILE" ||
  fail "vscode global dry-run must merge into the VS Code user settings file"
printf '%s\n' "$vs_global_dry" | grep -q 'chat.instructionsFilesLocations' ||
  fail "vscode global dry-run must name the settings-map key"
printf '%s\n' "$vs_global_dry" | grep -Fq '"~/.claude/rules":false' ||
  fail "vscode global dry-run must report the ~/.claude/rules false entry"
[[ ! -e "${HOME_DIR}/.copilot" ]] || fail "vscode global dry-run wrote under HOME"

vs_project_dry="$(HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target vscode --dry-run)"
vs_project_gen="$(printf '%s\n' "$vs_project_dry" | grep -c 'would-gen' || true)"
assert_eq "$vs_project_gen" "1" "vscode project dry-run should report exactly one generated style file"
printf '%s\n' "$vs_project_dry" | grep -q "$VS_PROJECT_FILE" ||
  fail "vscode project dry-run missing the project instructions write"
if printf '%s\n' "$vs_project_dry" | grep -q 'would-merge'; then
  fail "vscode project dry-run must not merge a settings key"
fi
if printf '%s\n' "$vs_project_dry" | grep -vE '^(Config|Deploy log|Config source):' | grep -q "${HOME_DIR}/"; then
  fail "vscode project dry-run must not resolve paths under HOME"
fi

# A sibling instructions file in the project root survives deploy and uninstall.
VS_PROJECT_SIBLING="${PROJECT_DIR}/.github/instructions/keep-sibling.instructions.md"
mkdir -p "${PROJECT_DIR}/.github/instructions"
printf '%s\n' '---' 'applyTo: "**"' '---' 'pre-existing sibling instructions' > "$VS_PROJECT_SIBLING"
VS_PROJECT_SIBLING_SAVED="${SCRATCH}/keep-sibling.instructions.md"
cp "$VS_PROJECT_SIBLING" "$VS_PROJECT_SIBLING_SAVED"

HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target vscode >/dev/null
assert_file "$VS_PROJECT_FILE"
# Project frontmatter scopes the rule to every file, so it is always-on.
awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$VS_PROJECT_FILE" | grep -q 'applyTo: "\*\*"' ||
  fail "vscode project instructions file must carry applyTo: \"**\""
if grep -qE 'keep-coding-instructions|force-for-plugin' "$VS_PROJECT_FILE"; then
  fail "vscode instructions file must not carry Claude output-style frontmatter keys"
fi
vs_eb="$(tr '\n' ' ' < "$VS_PROJECT_FILE" | grep -o '<engineering_behavior>[^<]*</engineering_behavior>' || true)"
[[ -n "$vs_eb" ]] || fail "vscode instructions file missing <engineering_behavior>"
printf '%s\n' "$vs_eb" | grep -qi 'named prose surfaces' ||
  fail "vscode engineering_behavior must name prose surfaces"
printf '%s\n' "$vs_eb" | grep -qi "Copilot's defaults" ||
  fail "vscode engineering_behavior must name Copilot's defaults"
printf '%s\n' "$vs_eb" | grep -qi 'append' ||
  fail "vscode engineering_behavior must state the harness only appends"
if grep -qF "[chat.instructionsFilesLocations]" "$VS_LOG" 2>/dev/null; then
  fail "vscode project deploy must not merge a settings key"
fi
cmp -s "$VS_PROJECT_SIBLING_SAVED" "$VS_PROJECT_SIBLING" ||
  fail "vscode project deploy changed a pre-existing sibling instructions file"

HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --project-dir "$PROJECT_DIR" --type style --target vscode >/dev/null
[[ ! -e "$VS_PROJECT_FILE" ]] || fail "vscode project uninstall left the deployed instructions file"
cmp -s "$VS_PROJECT_SIBLING_SAVED" "$VS_PROJECT_SIBLING" ||
  fail "vscode project uninstall changed a pre-existing sibling instructions file"

# Global real deploy: seed an unrelated entry in the settings map and an
# unrelated key, so the merge has to keep both. The instructions file is the
# body alone, with no frontmatter.
mkdir -p "${VS_SETTINGS_FILE%/*}"
printf '%s\n' '{"editor.fontSize":13,"chat.instructionsFilesLocations":{"/foreign/entry":true}}' > "$VS_SETTINGS_FILE"
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target vscode --clear-backups >/dev/null
assert_file "$VS_GLOBAL_FILE"
if grep -qx -- '---' "$VS_GLOBAL_FILE"; then
  fail "vscode global instructions file must be the body alone, with no frontmatter"
fi
if grep -qE 'keep-coding-instructions|force-for-plugin' "$VS_GLOBAL_FILE"; then
  fail "vscode global instructions file must not carry Claude output-style frontmatter keys"
fi
assert_eq "$(jq -c '.["chat.instructionsFilesLocations"]' "$VS_SETTINGS_FILE")" \
  '{"/foreign/entry":true,"~/.claude/rules":false}' \
  "vscode global deploy must add its entry and keep the foreign entry"
assert_eq "$(jq -c '.["editor.fontSize"]' "$VS_SETTINGS_FILE")" "13" \
  "vscode global deploy must leave every other settings key untouched"
assert_eq "$(awk -F'\t' -v p="${VS_SETTINGS_FILE}[chat.instructionsFilesLocations]" '$1==p{print $5; exit}' "$VS_LOG")" \
  '{"/foreign/entry":true}' \
  "vscode global deploy must record the settings map's prior value"

HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --global --type style --target vscode >/dev/null
[[ ! -e "$VS_GLOBAL_FILE" ]] || fail "vscode global uninstall left the deployed instructions file"
assert_eq "$(jq -c '.["chat.instructionsFilesLocations"]' "$VS_SETTINGS_FILE")" \
  '{"/foreign/entry":true}' \
  "vscode global uninstall must restore the settings map's recorded prior"
assert_eq "$(jq -c '.["editor.fontSize"]' "$VS_SETTINGS_FILE")" "13" \
  "vscode global uninstall must leave every other settings key untouched"

# A fresh machine has no VS Code settings file at all: the deploy creates the
# directory and the file, records @absent, and uninstall removes the key rather
# than leaving an empty map.
rm -rf "${VS_SETTINGS_FILE%/*}"
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target vscode --clear-backups >/dev/null
assert_file "$VS_SETTINGS_FILE"
assert_eq "$(jq -c '.["chat.instructionsFilesLocations"]' "$VS_SETTINGS_FILE")" \
  '{"~/.claude/rules":false}' \
  "vscode global deploy must create the settings file and map when both were absent"
HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$VS_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --global --type style --target vscode >/dev/null
assert_eq "$(jq -r 'has("chat.instructionsFilesLocations")' "$VS_SETTINGS_FILE")" "false" \
  "vscode global uninstall must remove a key whose prior was @absent"
jq -e . "$VS_SETTINGS_FILE" >/dev/null ||
  fail "vscode settings file must stay valid JSON after uninstall"

# --- Output-style shadow reporting and the global override caveat ---
# A --global run reports a shadowing value in this deploy's own repository.
# The staged sandbox root stands in for the checkout, so these scenarios read
# and write $SANDBOX_ROOT/.claude and leave this checkout untouched; cleanup
# removes the whole staged tree.
REPO_CLAUDE_DIR="${SANDBOX_ROOT}/.claude"
REPO_SETTINGS_LOCAL="${REPO_CLAUDE_DIR}/settings.local.json"
REPO_SETTINGS="${REPO_CLAUDE_DIR}/settings.json"

mkdir -p "$REPO_CLAUDE_DIR"

local_style_project="${SCRATCH}/local-style-project"
mkdir -p "$local_style_project/.claude"

shadow_count() {
  printf '%s\n' "$1" | grep -c 'shadow' || true
}

caveat_count() {
  printf '%s\n' "$1" | grep -c 'caveat' || true
}

# The diagnostic lines alone, so a dry-run comparison ignores the
# mode-labelled copy/merge/backup lines this task does not change.
diagnostic_lines() {
  printf '%s\n' "$1" | grep -E 'shadow|caveat' || true
}

assert_shadow_warning() {
  local out="$1" file="$2" shadow_value="$3" deployed_value="$4" frame="$5"
  local line
  assert_eq "$(shadow_count "$out")" "1" "expected exactly one shadow warning"
  line="$(printf '%s\n' "$out" | grep 'shadow')"
  printf '%s\n' "$line" | grep -qF "$file" ||
    fail "shadow warning missing the shadowing file path: $file"
  printf '%s\n' "$line" | grep -qF "$shadow_value" ||
    fail "shadow warning missing the shadowing value: $shadow_value"
  printf '%s\n' "$line" | grep -qF "$deployed_value" ||
    fail "shadow warning missing the deployed value: $deployed_value"
  printf '%s\n' "$line" | grep -qF '/config' ||
    fail "shadow warning missing the /config remedy"
  printf '%s\n' "$line" | grep -qi 'remove' ||
    fail "shadow warning missing the remove-the-key remedy"
  printf '%s\n' "$line" | grep -qiF "$frame" ||
    fail "shadow warning missing its frame: $frame"
}

assert_global_caveat() {
  local out="$1" line
  assert_eq "$(caveat_count "$out")" "1" "expected exactly one global caveat line"
  line="$(printf '%s\n' "$out" | grep 'caveat')"
  printf '%s\n' "$line" | grep -qi 'user level' ||
    fail "caveat line must name the user-level merge"
  printf '%s\n' "$line" | grep -qi 'overrides' ||
    fail "caveat line must name the project-level override"
  printf '%s\n' "$line" | grep -qF '.claude/settings.local.json' ||
    fail "caveat line must name .claude/settings.local.json"
}

run_project_style() {
  HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$DEPLOY_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$local_style_project" --type style --target claude "$@"
}

run_global_style() {
  HOME="$HOME_DIR" DEPLOYED_ARTIFACTS_LOG="$DEPLOY_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type style --target claude --clear-backups "$@"
}

reset_local_style_project() {
  rm -f "$local_style_project/.claude/settings.json" "$local_style_project/.claude/settings.local.json"
}

# A divergent local value warns with the file, both values, and the remedy.
reset_local_style_project
printf '%s\n' '{"outputStyle":"Explanatory"}' > "$local_style_project/.claude/settings.local.json"
project_shadow="$(run_project_style)" ||
  fail "project-dir deploy with a shadowed style must exit 0"
assert_shadow_warning "$project_shadow" \
  "$local_style_project/.claude/settings.local.json" "Explanatory" "natural-language" \
  "this project's local settings"

# An agreeing local value stays silent.
reset_local_style_project
printf '%s\n' '{"outputStyle":"natural-language"}' > "$local_style_project/.claude/settings.local.json"
project_agree="$(run_project_style)"
assert_eq "$(shadow_count "$project_agree")" "0" "agreeing local value must not warn"

# An absent local file stays silent.
reset_local_style_project
project_absent="$(run_project_style)"
assert_eq "$(shadow_count "$project_absent")" "0" "absent local settings must not warn"

# A local file without the key stays silent.
printf '%s\n' '{"permissions":{"allow":[]}}' > "$local_style_project/.claude/settings.local.json"
project_no_key="$(run_project_style)"
assert_eq "$(shadow_count "$project_no_key")" "0" "local settings without outputStyle must not warn"

# A project-dir run never prints the user-level caveat.
assert_eq "$(caveat_count "$project_shadow")" "0" "project-dir deploy must not print the global caveat"

# Global scope: the caveat is unconditional, and a clean checkout warns nothing.
printf '%s\n' '{"permissions":{"allow":[]}}' > "$REPO_SETTINGS_LOCAL"
rm -f "$REPO_SETTINGS"
global_clean="$(run_global_style)"
assert_global_caveat "$global_clean"
assert_eq "$(shadow_count "$global_clean")" "0" "clean checkout settings must not warn"

# Global scope: a divergent value in this checkout's own settings.local.json
# warns and names that file as the deploy's own repository.
printf '%s\n' '{"outputStyle":"Explanatory"}' > "$REPO_SETTINGS_LOCAL"
global_local_shadow="$(run_global_style)"
assert_global_caveat "$global_local_shadow"
assert_shadow_warning "$global_local_shadow" \
  "$REPO_SETTINGS_LOCAL" "Explanatory" "natural-language" \
  "this deploy's own repository"

# Removing the staged key leaves the caveat and drops the warning.
printf '%s\n' '{"permissions":{"allow":[]}}' > "$REPO_SETTINGS_LOCAL"
global_local_clean="$(run_global_style)"
assert_global_caveat "$global_local_clean"
assert_eq "$(shadow_count "$global_local_clean")" "0" "removed local key must stop the warning"

# Global scope: a divergent value in this checkout's own settings.json warns
# the same way. The file is created when absent and removed on exit.
printf '%s\n' '{"outputStyle":"Learning"}' > "$REPO_SETTINGS"
global_repo_shadow="$(run_global_style)"
assert_global_caveat "$global_repo_shadow"
assert_shadow_warning "$global_repo_shadow" \
  "$REPO_SETTINGS" "Learning" "natural-language" \
  "this deploy's own repository"

rm -f "$REPO_SETTINGS"
global_repo_clean="$(run_global_style)"
assert_global_caveat "$global_repo_clean"
assert_eq "$(shadow_count "$global_repo_clean")" "0" "removed settings value must stop the warning"

# Dry runs print the same diagnostic lines as the real run in each scope.
reset_local_style_project
printf '%s\n' '{"outputStyle":"Explanatory"}' > "$local_style_project/.claude/settings.local.json"
project_real="$(run_project_style)"
project_dry_shadow="$(run_project_style --dry-run)"
assert_eq "$(diagnostic_lines "$project_real")" "$(diagnostic_lines "$project_dry_shadow")" \
  "project-dir dry-run diagnostics must match the real run"

printf '%s\n' '{"outputStyle":"Explanatory"}' > "$REPO_SETTINGS_LOCAL"
rm -f "$REPO_SETTINGS"
global_real="$(run_global_style)"
global_dry_shadow="$(run_global_style --dry-run)"
assert_eq "$(diagnostic_lines "$global_real")" "$(diagnostic_lines "$global_dry_shadow")" \
  "global dry-run diagnostics must match the real run"

# The staged sandbox absorbed every "repo" context read; this checkout's own
# .claude settings must be byte-identical to the snapshot taken at entry.
assert_eq "$(repo_claude_snapshot)" "$repo_claude_before" \
  "style harness must leave this checkout's .claude settings untouched"

# ---------------------------------------------------------------------------
# Codex: whole-prompt style derivation
#
# Codex carries one instructions slot, so the style deploy derives the
# configured model's base instructions from `codex debug models`, substitutes
# the style-owned headings, and points model_instructions_file at the result.
# Every scenario below runs from its own scratch HOME and deploy log, and the
# stub binary answers `--version` and the catalog call with fixture text.
# ---------------------------------------------------------------------------
CODEX_SCRATCH="${SCRATCH}/codex"
CODEX_REPO="${CODEX_SCRATCH}/repo"
CODEX_EMPTY_APPS="${CODEX_SCRATCH}/no-applications"
mkdir -p "$CODEX_SCRATCH" "$CODEX_EMPTY_APPS"
mkdir -p "$CODEX_REPO/deployment" "$CODEX_REPO/plugins"
cp "$REPO_ROOT/deployment/deployment.sh" "$CODEX_REPO/deployment/deployment.sh"
cp "$REPO_ROOT/deployment/ai_asset_deploy.conf.template" "$CODEX_REPO/deployment/ai_asset_deploy.conf.template"
cp -R "$REPO_ROOT/styles" "$CODEX_REPO/styles"
CODEX_DEPLOY="${CODEX_REPO}/deployment/deployment.sh"
CODEX_STUB_VERSION="codex-cli 9.9.9-test"

codex_plain() {
  perl -pe 's/\e\[[0-9;]*m//g'
}

assert_present() {  # file pattern message
  grep -qF -- "$2" "$1" || fail "$3"
}

assert_present_re() {  # file pattern message
  grep -qE -- "$2" "$1" || fail "$3"
}

assert_absent() {  # file pattern message
  if grep -qF -- "$2" "$1"; then fail "$3"; fi
}

assert_absent_re() {  # file pattern message
  if grep -qE -- "$2" "$1"; then fail "$3"; fi
}

assert_span_identical() {  # derived generated heading
  python3 - "$1" "$2" "$3" <<'PY' || fail "untouched heading span changed: $3"
import re
import sys

def span(path, heading):
    lines = open(path, encoding="utf-8").read().splitlines()
    heads = [i for i, line in enumerate(lines) if re.match(r"^#{1,6} ", line)]
    for position, index in enumerate(heads):
        if lines[index] == heading:
            end = heads[position + 1] if position + 1 < len(heads) else len(lines)
            return lines[index:end]
    return None

derived = span(sys.argv[1], sys.argv[3])
generated = span(sys.argv[2], sys.argv[3])
if derived is None or generated is None or derived != generated:
    sys.exit(1)
PY
}

assert_paragraphs() {  # file text message
  python3 - "$1" "$2" <<'PY' || fail "$3"
import sys
paras = [p.strip() for p in open(sys.argv[1], encoding="utf-8").read().split("\n\n")]
if sys.argv[2] not in paras:
    sys.exit(1)
PY
}

codex_catalog() {  # out slug derived
  jq -n --rawfile bi "$3" --arg slug "$2" \
    '{models:[{slug:$slug,base_instructions:$bi}]}' > "$1"
}

make_codex_stub() {  # path catalog version [mode]
  local path="$1" catalog="$2" version="$3" mode="${4:-ok}"
  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'case "$1" in'
    printf '  --version) echo "%s" ;;\n' "$version"
    if [[ "$mode" == "fail" ]]; then
      printf '%s\n' '  debug) echo "catalog unavailable" >&2; exit 7 ;;'
    else
      printf '  debug) cat "%s" ;;\n' "$catalog"
    fi
    printf '%s\n' '  *) exit 1 ;;'
    printf '%s\n' 'esac'
  } > "$path"
  chmod +x "$path"
}

seed_codex_home() {  # home [model] [extra-toml]
  local home="$1" model="${2-gpt-test}" extra="${3:-}"
  mkdir -p "$home/.codex" "$home/.ai_asset_deploy"
  : > "$home/.codex/config.toml"
  if [[ -n "$model" ]]; then printf 'model = "%s"\n' "$model" >> "$home/.codex/config.toml"; fi
  if [[ -n "$extra" ]]; then printf '%s\n' "$extra" >> "$home/.codex/config.toml"; fi
  cp "$CONF_TEMPLATE" "$home/.ai_asset_deploy/config"
  printf '\n#codex\nstyle:natural-language\n' >> "$home/.ai_asset_deploy/config"
}

codex_run() {  # home log system-root args...
  local home="$1" log="$2" sysroot="$3"
  shift 3
  HOME="$home" CODEX_HOME="" CODEX_SYSTEM_BUNDLE_ROOT="$sysroot" \
    DEPLOYED_ARTIFACTS_LOG="$log" "$DEPLOY_BASH" "$CODEX_DEPLOY" "$@"
}

codex_run_bin() {  # home log system-root bin args...
  local home="$1" log="$2" sysroot="$3" bin="$4"
  shift 4
  HOME="$home" CODEX_HOME="" CODEX_BIN="$bin" CODEX_SYSTEM_BUNDLE_ROOT="$sysroot" \
    DEPLOYED_ARTIFACTS_LOG="$log" "$DEPLOY_BASH" "$CODEX_DEPLOY" "$@"
}

codex_run_home() {  # home log system-root codex-home args...
  local home="$1" log="$2" sysroot="$3" codexhome="$4"
  shift 4
  HOME="$home" CODEX_HOME="$codexhome" CODEX_SYSTEM_BUNDLE_ROOT="$sysroot" \
    DEPLOYED_ARTIFACTS_LOG="$log" "$DEPLOY_BASH" "$CODEX_DEPLOY" "$@"
}

# --- Static documentation and configuration checks ---
assert_present "$CODEX_DEPLOY" 'read by the Claude and Codex' \
  "deployment.sh style directive must name both arms"
assert_present "$CONF_TEMPLATE" 'Claude and Codex' \
  "config template style directive must name both arms"
if grep -qE '^[[:space:]]*style:' "$CONF_TEMPLATE"; then
  fail "committed config template must carry no style: activation"
fi
assert_present "$REPO_ROOT/deployment/README.md" 'The Claude arm merges settings `outputStyle` at the deploy scope; the Codex arm derives' \
  "README style directive row must name both arms"
codex_row="$(grep -F '| OpenAI Codex |' "$REPO_ROOT/deployment/README.md" | head -n 1)"
printf '%s\n' "$codex_row" | grep -qF 'not yet' &&
  fail "README Codex Target Layout Styles cell must no longer read 'not yet'"
printf '%s\n' "$codex_row" | grep -qF 'model_instructions_file' ||
  fail "README Codex Target Layout Styles cell must name the configuration key"
grep -F '| style (`styles/*.md`) | OpenAI Codex |' "$REPO_ROOT/deployment/README.md" >/dev/null ||
  fail "README Generated Formats must gain a Codex style row"
readme_codex_style="$(grep -F '| style (`styles/*.md`) | OpenAI Codex |' "$REPO_ROOT/deployment/README.md")"
printf '%s\n' "$readme_codex_style" | grep -qF 'codex debug models' ||
  fail "README Codex style row must name the derivation source"
printf '%s\n' "$readme_codex_style" | grep -qF '# Personality' ||
  fail "README Codex style row must name a substituted section"
printf '%s\n' "$readme_codex_style" | grep -qF 'fails loudly' ||
  fail "README Codex style row must name the fail-loudly behaviour"
printf '%s\n' "$readme_codex_style" | grep -qF 'does not re-derive' ||
  fail "README Codex style row must state that the value does not re-derive"

# The fixture is shaped like the configured model: Technical communication and
# its PR subsection are present, Formatting rules sits beside Final answer, and
# two template tokens survive in an untouched section.
CODEX_DERIVED="${CODEX_SCRATCH}/derived.md"
cat > "$CODEX_DERIVED" <<'EOF'
You are Codex, an agent based on GPT-Test. You and the user share one workspace.

# Personality

OLD PERSONALITY BODY.

## Writing style

OLD WRITING BODY.

## Technical communication

Use plain language over jargon.

### Writing PR descriptions

OLD PR BODY.

# Working with the user

USER INTRO.

## Intermediate commentary

COMMENTARY SENTINEL.

## Final answer

OLD FINAL BODY.

### Formatting rules

Your answer is being rendered by an application for the user
FORMATTING SENTINEL.

### Visualizations

VISUALIZATION SENTINEL.

# Rules for getting work done

RULES SENTINEL.

# Using skills

SKILLS SENTINEL.

# Apps (Connectors)

Token {{connector_id}} and {{plugin_id}} stay.
EOF
CODEX_CATALOG="${CODEX_SCRATCH}/catalog.json"
codex_catalog "$CODEX_CATALOG" "gpt-test" "$CODEX_DERIVED"

# --- No binary: a clean skip, no write, no key ---
C1_HOME="${CODEX_SCRATCH}/c1-home"
C1_LOG="${CODEX_SCRATCH}/c1.log"
seed_codex_home "$C1_HOME" "gpt-test"
c1_out="$(codex_run "$C1_HOME" "$C1_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --dry-run 2>&1)"
c1_plain="$(printf '%s\n' "$c1_out" | codex_plain)"
printf '%s\n' "$c1_plain" | grep -q 'no Codex binary found' ||
  fail "no-binary dry run must report a clean skip"
if printf '%s\n' "$c1_plain" | grep -qE 'would-gen|would-merge'; then
  fail "no-binary dry run must report neither a generated-file write nor a key merge"
fi
[[ ! -e "${C1_HOME}/.codex/instructions/natural-language.md" ]] ||
  fail "no-binary dry run must write no generated file"
assert_absent "${C1_HOME}/.codex/config.toml" 'model_instructions_file' \
  "no-binary dry run must write no configuration key"

# --- CODEX_BIN stub: one generated-file write and one key merge in a dry run ---
C2_HOME="${CODEX_SCRATCH}/c2-home"
C2_LOG="${CODEX_SCRATCH}/c2.log"
C2_STUB="${CODEX_SCRATCH}/c2-bin/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
seed_codex_home "$C2_HOME" "gpt-test"
make_codex_stub "$C2_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
c2_out="$(codex_run_bin "$C2_HOME" "$C2_LOG" "$CODEX_EMPTY_APPS" "$C2_STUB" --global --type style --target codex --dry-run 2>&1)"
c2_plain="$(printf '%s\n' "$c2_out" | codex_plain)"
assert_eq "$(printf '%s\n' "$c2_plain" | grep -c 'would-gen' || true)" "1" \
  "CODEX_BIN dry run must report exactly one generated-file write"
assert_eq "$(printf '%s\n' "$c2_plain" | grep -c 'would-merge' || true)" "1" \
  "CODEX_BIN dry run must report exactly one configuration key merge"
printf '%s\n' "$c2_plain" | grep -qF "${C2_HOME}/.codex/instructions/natural-language.md" ||
  fail "CODEX_BIN dry run must name the generated-file destination"
printf '%s\n' "$c2_plain" | grep -qF "${C2_HOME}/.codex/config.toml" ||
  fail "CODEX_BIN dry run must name the configuration file"
[[ ! -e "${C2_HOME}/.codex/instructions/natural-language.md" ]] ||
  fail "dry run must not write the generated file"

# --- HOME-bundle stub: real deploy, substitutions, untouched spans ---
C3_HOME="${CODEX_SCRATCH}/c3-home"
C3_LOG="${CODEX_SCRATCH}/c3.log"
C3_STUB="${C3_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
seed_codex_home "$C3_HOME" "gpt-test"
make_codex_stub "$C3_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
c3_out="$(codex_run "$C3_HOME" "$C3_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups 2>&1)"
c3_plain="$(printf '%s\n' "$c3_out" | codex_plain)"
printf '%s\n' "$c3_plain" | grep -q 'generated' ||
  fail "HOME-bundle deploy must report the generated file"
printf '%s\n' "$c3_plain" | grep -q 'merged' ||
  fail "HOME-bundle deploy must report the configuration merge"
printf '%s\n' "$c3_plain" | grep -q 'no Codex binary' &&
  fail "HOME-bundle deploy must not report the no-binary skip"

C3_FILE="${C3_HOME}/.codex/instructions/natural-language.md"
assert_file "$C3_FILE"
assert_present "$C3_FILE" "Model: gpt-test" "generated header must name the configured model"
assert_present "$C3_FILE" "Codex version: ${CODEX_STUB_VERSION}" \
  "generated header must name the version the stub reported"

assert_absent "$C3_FILE" 'OLD PERSONALITY BODY' "Personality body must be replaced"
assert_present "$C3_FILE" 'Write like one person explaining something to another' \
  "Personality must carry the style objective"
assert_absent "$C3_FILE" 'OLD WRITING BODY' "Writing style body must be replaced"
assert_present "$C3_FILE" 'A plain fact can take ten words' \
  "Writing style must carry the style sentence rules"
assert_absent "$C3_FILE" 'OLD FINAL BODY' "Final answer body must be replaced"
assert_present "$C3_FILE" 'In a chat answer, the answer is in the first sentence.' \
  "Final answer must carry the style validations"
assert_absent "$C3_FILE" 'plain language over jargon' \
  "Technical communication clause must be removed"
assert_absent_re "$C3_FILE" '^## Technical communication$' \
  "Technical communication heading must be removed"
assert_absent_re "$C3_FILE" '^### Writing PR descriptions$' \
  "Writing PR descriptions heading must be removed"
assert_present "$C3_FILE" 'COMMENTARY SENTINEL.' \
  "Intermediate commentary must survive"
assert_present "$C3_FILE" 'VISUALIZATION SENTINEL.' \
  "Visualizations must survive"
assert_present "$C3_FILE" 'Your answer is being rendered by an application for the user' \
  "Formatting rules must survive"
assert_present "$C3_FILE" 'FORMATTING SENTINEL.' "Formatting rules body must survive"
assert_present "$C3_FILE" 'RULES SENTINEL.' "Operating sections must survive"
assert_present "$C3_FILE" 'SKILLS SENTINEL.' "Skill section must survive"

assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '# Working with the user'
assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '## Intermediate commentary'
assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '### Visualizations'
assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '### Formatting rules'
assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '# Rules for getting work done'
assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '# Using skills'
assert_span_identical "$CODEX_DERIVED" "$C3_FILE" '# Apps (Connectors)'

for tag in '<focus>' '<sentence_style>' '<paragraphs>' '<rule>' '<lists>' '<validation>' '<natural_language>'; do
  assert_absent "$C3_FILE" "$tag" "generated file must carry no style-body tag: $tag"
done
assert_absent "$C3_FILE" 'keep-coding-instructions' \
  "generated file must not reference Claude's flag mechanism"
assert_absent "$C3_FILE" 'force-for-plugin' \
  "generated file must carry no Claude output-style key"
assert_present "$C3_FILE" '<engineering_behavior>The wording rules govern prose. Coding, tool-use, and verification behaviour come from the Codex operating sections kept from the derived text.</engineering_behavior>' \
  "generated file must carry the Codex engineering-behaviour clause"

assert_eq "$(grep -cF 'These rules govern documents and other multi-paragraph text.' "$C3_FILE" || true)" "1" \
  "paragraphs lead-in must appear once"
assert_paragraphs "$C3_FILE" 'These rules govern documents and other multi-paragraph text.' \
  "paragraphs lead-in must be a paragraph of its own"
assert_paragraphs "$C3_FILE" 'In a chat answer, put the answer in the first sentence. Add only what the reader needs after it.' \
  "answer_first must be a paragraph of its own"
assert_paragraphs "$C3_FILE" 'In a chat answer, answer the question that was asked. Leave out background, alternatives, and history the reader did not ask for.' \
  "answer_what_was_asked must be a paragraph of its own"
assert_paragraphs "$C3_FILE" "$(sed -n 's/^    <one_theme>\(.*\)<\/one_theme>$/\1/p' "$REPO_ROOT/styles/natural-language.md")" \
  "one_theme must be a paragraph of its own"
assert_paragraphs "$C3_FILE" "$(sed -n 's/^    <section_lead>\(.*\)<\/section_lead>$/\1/p' "$REPO_ROOT/styles/natural-language.md")" \
  "section_lead must be a paragraph of its own"
assert_paragraphs "$C3_FILE" "$(sed -n 's/^    <short_sentences>\(.*\)<\/short_sentences>$/\1/p' "$REPO_ROOT/styles/natural-language.md")" \
  "short_sentences must be a paragraph of its own"
assert_paragraphs "$C3_FILE" "$(sed -n 's/^    <one_idea>\(.*\)<\/one_idea>$/\1/p' "$REPO_ROOT/styles/natural-language.md")" \
  "one_idea must be a paragraph of its own"

assert_eq "$(grep -o '{{' "$C3_FILE" | wc -l | tr -d '[:space:]')" "2" \
  "generated file must carry exactly the two derived template tokens"
assert_present "$C3_FILE" '{{connector_id}}' "connector token must survive byte-for-byte"
assert_present "$C3_FILE" '{{plugin_id}}' "plugin token must survive byte-for-byte"

replaced_line="$(grep '^Replaced headings:' "$C3_FILE")"
untouched_line="$(grep '^Untouched headings:' "$C3_FILE")"
for heading in '# Personality' '## Writing style' '## Final answer' '## Technical communication' '### Writing PR descriptions'; do
  printf '%s\n' "$replaced_line" | grep -qF "$heading" ||
    fail "replaced-headings header must list: $heading"
done
printf '%s\n' "$replaced_line" | grep -qF '### Formatting rules' &&
  fail "Formatting rules must not be listed among the replaced headings"
for heading in '# Working with the user' '## Intermediate commentary' '### Visualizations'; do
  printf '%s\n' "$untouched_line" | grep -qF "$heading" ||
    fail "untouched-headings header must list: $heading"
done

python3 - "$C3_HOME/.codex/config.toml" "$C3_FILE" <<'PY' || fail "Codex config must parse as TOML and point at the generated file"
import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
if data.get("model_instructions_file") != sys.argv[2]:
    sys.exit(1)
PY
assert_eq "$(awk -F'\t' -v p="${C3_HOME}/.codex/config.toml[model_instructions_file]" '$1==p{print $5; exit}' "$C3_LOG")" "@absent" \
  "first-write prior for the missing key must be @absent"
assert_eq "$(grep -cF "${C3_FILE}"$'\t' "$C3_LOG" || true)" "1" \
  "one deploy must log exactly one line for the generated file"

# --- Overwrite: a stale generated file is replaced by a fresh derivation ---
printf '%s\n' 'SENTINEL BODY' 'Model: other-model' 'Codex version: codex-cli 0.0.1' > "$C3_FILE"
codex_run "$C3_HOME" "$C3_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups >/dev/null
assert_absent "$C3_FILE" 'SENTINEL BODY' "redeploy must replace stale generated content"
assert_absent "$C3_FILE" 'Model: other-model' "redeploy must replace the stale model header"
assert_present "$C3_FILE" 'Model: gpt-test' "redeploy must name the current model"
assert_present "$C3_FILE" "Codex version: ${CODEX_STUB_VERSION}" \
  "redeploy must name the current Codex version"

# --- A derived text shaped like gpt-6.2-astra: Final answer under Personality ---
# Proved by sourcing the deploy script and calling the derivation function
# directly, as the acceptance asks, so the substitution is exercised on that
# shape without depending on a model choice.
C3B_HOME="${CODEX_SCRATCH}/c3b-home"
C3B_LOG="${CODEX_SCRATCH}/c3b.log"
C3B_DEST="${C3B_HOME}/.codex/instructions/natural-language.md"
seed_codex_home "$C3B_HOME" "gpt-test"
C3B_DERIVED="${CODEX_SCRATCH}/c3b-derived.md"
cat > "$C3B_DERIVED" <<'EOF'
# Personality

OLD PERSONALITY BODY.

## Final answer

OLD FINAL BODY.

## Writing style

OLD WRITING BODY.

## Technical communication

Use plain language over jargon.

### Writing PR descriptions

OLD PR BODY.

# Working with the user

USER INTRO.

## Intermediate commentary

COMMENTARY SENTINEL.

### Visualizations

VISUALIZATION SENTINEL.
EOF
C3B_CATALOG="${CODEX_SCRATCH}/c3b-catalog.json"
codex_catalog "$C3B_CATALOG" "gpt-test" "$C3B_DERIVED"
C3B_STUB="${CODEX_SCRATCH}/c3b-bin/codex"
make_codex_stub "$C3B_STUB" "$C3B_CATALOG" "$CODEX_STUB_VERSION"
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  HOME="$C3B_HOME"
  unset CODEX_HOME
  export HOME
  # shellcheck source=/dev/null
  source "$CODEX_DEPLOY"
  CODEX_BIN="$C3B_STUB"
  CODEX_SYSTEM_BUNDLE_ROOT="$CODEX_EMPTY_APPS"
  DEPLOYED_ARTIFACTS_LOG="$C3B_LOG"
  DRY_RUN=false
  generate_codex_style_file "$REPO_ROOT/styles/natural-language.md" "$C3B_DEST" "codex" "style"
)
assert_file "$C3B_DEST"
assert_absent "$C3B_DEST" 'OLD PERSONALITY BODY' "6.2 shape: Personality must be replaced"
assert_present "$C3B_DEST" 'Write like one person explaining something to another' \
  "6.2 shape: Personality must carry the style objective"
assert_absent "$C3B_DEST" 'OLD FINAL BODY' "6.2 shape: Final answer must be replaced"
assert_present "$C3B_DEST" 'In a chat answer, the answer is in the first sentence.' \
  "6.2 shape: Final answer must carry the style validations"
assert_absent "$C3B_DEST" 'OLD WRITING BODY' "6.2 shape: Writing style must be replaced"
assert_absent "$C3B_DEST" 'plain language over jargon' "6.2 shape: removed clause must be gone"
assert_span_identical "$C3B_DERIVED" "$C3B_DEST" '# Working with the user'
assert_span_identical "$C3B_DERIVED" "$C3B_DEST" '## Intermediate commentary'
assert_span_identical "$C3B_DERIVED" "$C3B_DEST" '### Visualizations'
c3b_replaced="$(grep '^Replaced headings:' "$C3B_DEST")"
for heading in '# Personality' '## Writing style' '## Final answer'; do
  printf '%s\n' "$c3b_replaced" | grep -qF "$heading" ||
    fail "6.2 shape: replaced-headings header must list: $heading"
done

# --- A config with no model key skips the style and writes nothing ---
C4_HOME="${CODEX_SCRATCH}/c4-home"
C4_LOG="${CODEX_SCRATCH}/c4.log"
seed_codex_home "$C4_HOME" ""
C4_STUB="${C4_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C4_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
c4_out="$(codex_run "$C4_HOME" "$C4_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups 2>&1)"
c4_plain="$(printf '%s\n' "$c4_out" | codex_plain)"
printf '%s\n' "$c4_plain" | grep -q 'no model key' ||
  fail "a config with no model key must skip with a warning"
[[ ! -e "${C4_HOME}/.codex/instructions/natural-language.md" ]] ||
  fail "a config with no model key must write no generated file"
assert_absent "${C4_HOME}/.codex/config.toml" 'model_instructions_file' \
  "a config with no model key must write no configuration key"

# --- TOML preservation: other keys, a table, and comments survive ---
C5_HOME="${CODEX_SCRATCH}/c5-home"
C5_LOG="${CODEX_SCRATCH}/c5.log"
seed_codex_home "$C5_HOME" "gpt-test"
C5_STUB="${C5_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C5_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
cat > "$C5_HOME/.codex/config.toml" <<'EOF'
# top comment kept
model = "gpt-test" # trailing comment kept
model_reasoning_effort = "xhigh"

[profiles.fast]
model = "gpt-other"
EOF
codex_run "$C5_HOME" "$C5_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups >/dev/null
python3 - "$C5_HOME/.codex/config.toml" "${C5_HOME}/.codex/instructions/natural-language.md" <<'PY' || fail "TOML merge must keep every other key, table, and comment"
import sys, tomllib
text = open(sys.argv[1], encoding="utf-8").read()
data = tomllib.loads(text)
assert data["model"] == "gpt-test"
assert data["model_reasoning_effort"] == "xhigh"
assert data["profiles"]["fast"]["model"] == "gpt-other"
assert data["model_instructions_file"] == sys.argv[2]
assert "# top comment kept" in text
assert "# trailing comment kept" in text
PY

# --- Prior restore: an existing key comes back on uninstall ---
C6_HOME="${CODEX_SCRATCH}/c6-home"
C6_LOG="${CODEX_SCRATCH}/c6.log"
seed_codex_home "$C6_HOME" "gpt-test"
C6_STUB="${C6_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C6_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
printf 'model_instructions_file = "/prior/instructions.md"\n' >> "$C6_HOME/.codex/config.toml"
codex_run "$C6_HOME" "$C6_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups >/dev/null
c6_out="$(codex_run "$C6_HOME" "$C6_LOG" "$CODEX_EMPTY_APPS" --uninstall --global --type style --target codex 2>&1)"
c6_plain="$(printf '%s\n' "$c6_out" | codex_plain)"
printf '%s\n' "$c6_plain" | grep -q 'removed' ||
  fail "uninstall must report the restored configuration entry removed"
printf '%s\n' "$c6_plain" | grep -q 'failed' &&
  fail "uninstall must not report a restored configuration entry failed"
python3 - "$C6_HOME/.codex/config.toml" <<'PY' || fail "uninstall must restore the original model_instructions_file value"
import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
if data.get("model_instructions_file") != "/prior/instructions.md":
    sys.exit(1)
PY
assert_eq "$(grep -c 'model_instructions_file' "$C6_LOG" || true)" "0" \
  "uninstall must leave no log line for the restored key"

# --- Missing style-owned heading: fail loudly, write nothing, other targets still deploy ---
C7_HOME="${CODEX_SCRATCH}/c7-home"
C7_LOG="${CODEX_SCRATCH}/c7.log"
seed_codex_home "$C7_HOME" "gpt-test"
printf '\n#claude\nstyle:natural-language\n' >> "$C7_HOME/.ai_asset_deploy/config"
C7_STUB="${C7_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
C7_DERIVED="${CODEX_SCRATCH}/c7-derived.md"
cat > "$C7_DERIVED" <<'EOF'
# Personality

OLD PERSONALITY BODY.

## Final answer

OLD FINAL BODY.

# Working with the user

USER INTRO.
EOF
C7_CATALOG="${CODEX_SCRATCH}/c7-catalog.json"
codex_catalog "$C7_CATALOG" "gpt-test" "$C7_DERIVED"
make_codex_stub "$C7_STUB" "$C7_CATALOG" "$CODEX_STUB_VERSION"
c7_out="$(codex_run "$C7_HOME" "$C7_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex,claude --clear-backups 2>&1)"
c7_plain="$(printf '%s\n' "$c7_out" | codex_plain)"
printf '%s\n' "$c7_plain" | grep -qF "missing style-owned heading(s) '## Writing style' in the Codex ${CODEX_STUB_VERSION} catalog" ||
  fail "missing heading must name the heading and the Codex version"
printf '%s\n' "$c7_plain" | grep -q 'failed' ||
  fail "missing heading must fail the Codex style"
[[ ! -e "${C7_HOME}/.codex/instructions/natural-language.md" ]] ||
  fail "missing heading must write no generated file"
assert_absent "${C7_HOME}/.codex/config.toml" 'model_instructions_file' \
  "missing heading must write no configuration key"
assert_file "${C7_HOME}/.claude/output-styles/natural-language.md"

# --- Catalog read failures skip only the Codex style ---
C8_HOME="${CODEX_SCRATCH}/c8-home"
C8_LOG="${CODEX_SCRATCH}/c8.log"
seed_codex_home "$C8_HOME" "gpt-test"
C8_DEST="${C8_HOME}/.codex/instructions/natural-language.md"
C8_FAIL_STUB="${CODEX_SCRATCH}/c8-fail-bin/codex"
make_codex_stub "$C8_FAIL_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION" fail
c8_out="$(
  (
    set -- --uninstall
    DEPLOYMENT_SH_SKIP_MAIN=1
    HOME="$C8_HOME"
    unset CODEX_HOME
    export HOME
    # shellcheck source=/dev/null
    source "$CODEX_DEPLOY"
    CODEX_BIN="$C8_FAIL_STUB"
    CODEX_SYSTEM_BUNDLE_ROOT="$CODEX_EMPTY_APPS"
    DEPLOYED_ARTIFACTS_LOG="$C8_LOG"
    DRY_RUN=false
    generate_codex_style_file "$REPO_ROOT/styles/natural-language.md" "$C8_DEST" "codex" "style"
  ) 2>&1
)"
c8_plain="$(printf '%s\n' "$c8_out" | codex_plain)"
printf '%s\n' "$c8_plain" | grep -q 'debug models failed' ||
  fail "a failing catalog render must name the cause"
[[ ! -e "$C8_DEST" ]] || fail "a failing catalog render must write no generated file"
assert_absent "${C8_HOME}/.codex/config.toml" 'model_instructions_file' \
  "a failing catalog render must write no configuration key"
# A full run with the same failure still deploys every other target.
printf '\n#claude\nstyle:natural-language\n' >> "$C8_HOME/.ai_asset_deploy/config"
C8_STUB="${C8_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C8_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION" fail
c8_full="$(codex_run "$C8_HOME" "$C8_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex,claude --clear-backups 2>&1)"
c8_full_plain="$(printf '%s\n' "$c8_full" | codex_plain)"
printf '%s\n' "$c8_full_plain" | grep -q 'debug models failed' ||
  fail "a full run with a failing catalog must report the skip"
assert_file "${C8_HOME}/.claude/output-styles/natural-language.md"
[[ ! -e "$C8_DEST" ]] || fail "a full run with a failing catalog must write no generated file"

C9_HOME="${CODEX_SCRATCH}/c9-home"
C9_LOG="${CODEX_SCRATCH}/c9.log"
seed_codex_home "$C9_HOME" "gpt-test"
C9_DEST="${C9_HOME}/.codex/instructions/natural-language.md"
C9_OTHER_CATALOG="${CODEX_SCRATCH}/c9-other-catalog.json"
jq -n --arg slug other '{models:[{slug:$slug,base_instructions:"x"}]}' > "$C9_OTHER_CATALOG"
C9_OTHER_STUB="${CODEX_SCRATCH}/c9-other-bin/codex"
make_codex_stub "$C9_OTHER_STUB" "$C9_OTHER_CATALOG" "$CODEX_STUB_VERSION"
# shellcheck disable=SC2034
c9_out="$(
  (
    set -- --uninstall
    DEPLOYMENT_SH_SKIP_MAIN=1
    HOME="$C9_HOME"
    unset CODEX_HOME
    export HOME
    # shellcheck source=/dev/null
    source "$CODEX_DEPLOY"
    CODEX_BIN="$C9_OTHER_STUB"
    CODEX_SYSTEM_BUNDLE_ROOT="$CODEX_EMPTY_APPS"
    DEPLOYED_ARTIFACTS_LOG="$C9_LOG"
    DRY_RUN=false
    generate_codex_style_file "$REPO_ROOT/styles/natural-language.md" "$C9_DEST" "codex" "style"
  ) 2>&1
)"
c9_plain="$(printf '%s\n' "$c9_out" | codex_plain)"
printf '%s\n' "$c9_plain" | grep -q "model 'gpt-test' has no base_instructions" ||
  fail "a catalog that omits the configured model must name the cause"
[[ ! -e "$C9_DEST" ]] || fail "a catalog that omits the model must write no generated file"
assert_absent "${C9_HOME}/.codex/config.toml" 'model_instructions_file' \
  "a catalog that omits the model must write no configuration key"

# --- personality = "none" produces the same file as an absent setting ---
C10A_HOME="${CODEX_SCRATCH}/c10a-home"
C10B_HOME="${CODEX_SCRATCH}/c10b-home"
C10A_LOG="${CODEX_SCRATCH}/c10a.log"
C10B_LOG="${CODEX_SCRATCH}/c10b.log"
seed_codex_home "$C10A_HOME" "gpt-test"
seed_codex_home "$C10B_HOME" "gpt-test" 'personality = "none"'
C10A_STUB="${C10A_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
C10B_STUB="${C10B_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C10A_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
make_codex_stub "$C10B_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
codex_run "$C10A_HOME" "$C10A_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups >/dev/null
codex_run "$C10B_HOME" "$C10B_LOG" "$CODEX_EMPTY_APPS" --global --type style --target codex --clear-backups >/dev/null
cmp -s "${C10A_HOME}/.codex/instructions/natural-language.md" \
  "${C10B_HOME}/.codex/instructions/natural-language.md" ||
  fail "personality = none must produce the same generated file as an absent setting"
assert_present "${C10B_HOME}/.codex/instructions/natural-language.md" \
  'Write like one person explaining something to another' \
  "personality = none must still carry the style Personality prose"

# --- CODEX_HOME relocates every Codex artefact ---
C11_HOME="${CODEX_SCRATCH}/c11-home"
C11_CODEX_HOME="${CODEX_SCRATCH}/c11-codex-home"
C11_LOG="${CODEX_SCRATCH}/c11.log"
mkdir -p "$C11_HOME/.ai_asset_deploy" "$C11_CODEX_HOME"
printf 'model = "gpt-test"\n' > "$C11_CODEX_HOME/config.toml"
cp "$CONF_TEMPLATE" "$C11_HOME/.ai_asset_deploy/config"
printf '\n#codex\nstyle:natural-language\n' >> "$C11_HOME/.ai_asset_deploy/config"
C11_STUB="${C11_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C11_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
codex_run_home "$C11_HOME" "$C11_LOG" "$CODEX_EMPTY_APPS" "$C11_CODEX_HOME" --global --type style --target codex --clear-backups >/dev/null
assert_file "${C11_CODEX_HOME}/instructions/natural-language.md"
assert_present "${C11_CODEX_HOME}/config.toml" 'model_instructions_file' \
  "CODEX_HOME deploy must merge the key into that tree's config"
[[ ! -e "${C11_HOME}/.codex" ]] ||
  fail "CODEX_HOME deploy must leave ~/.codex untouched"
codex_run_home "$C11_HOME" "$C11_LOG" "$CODEX_EMPTY_APPS" "$C11_CODEX_HOME" --uninstall --global --type style --target codex >/dev/null
[[ ! -e "${C11_CODEX_HOME}/instructions/natural-language.md" ]] ||
  fail "CODEX_HOME uninstall must remove the generated file"
assert_absent "${C11_CODEX_HOME}/config.toml" 'model_instructions_file' \
  "CODEX_HOME uninstall must remove the configuration key"

# logged_path_scope derives global under both Codex roots and the project for a
# project tree, whichever CODEX_HOME names.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  HOME="$C11_HOME"
  export HOME
  # shellcheck source=/dev/null
  source "$CODEX_DEPLOY"
  HOME_DIR="$C11_HOME"
  CODEX_HOME="$C11_CODEX_HOME"
  assert_eq "$(logged_path_scope "${C11_HOME}/.codex/instructions/x.md" codex)" "global" \
    "a ~/.codex path must derive global"
  assert_eq "$(logged_path_scope "${C11_CODEX_HOME}/instructions/x.md" codex)" "global" \
    "a CODEX_HOME path must derive global"
  project_dir="${CODEX_SCRATCH}/c11-project"
  assert_eq "$(logged_path_scope "${project_dir}/.codex/instructions/x.md" codex)" "$project_dir" \
    "a project .codex path must derive the project"
  assert_eq "$(logged_path_scope "${project_dir}/.agents/skills/x/SKILL.md" codex)" "$project_dir" \
    "a project .agents/skills path must derive the project"
)

# --- A second, non-active style file is skipped ---
C12_REPO="${CODEX_SCRATCH}/c12-repo"
mkdir -p "$C12_REPO/deployment" "$C12_REPO/plugins"
cp "$REPO_ROOT/deployment/deployment.sh" "$C12_REPO/deployment/deployment.sh"
cp "$REPO_ROOT/deployment/ai_asset_deploy.conf.template" "$C12_REPO/deployment/ai_asset_deploy.conf.template"
cp -R "$REPO_ROOT/styles" "$C12_REPO/styles"
cp "$C12_REPO/styles/natural-language.md" "$C12_REPO/styles/other-style.md"
C12_HOME="${CODEX_SCRATCH}/c12-home"
C12_LOG="${CODEX_SCRATCH}/c12.log"
seed_codex_home "$C12_HOME" "gpt-test"
C12_STUB="${C12_HOME}/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
make_codex_stub "$C12_STUB" "$CODEX_CATALOG" "$CODEX_STUB_VERSION"
c12_out="$(HOME="$C12_HOME" CODEX_HOME="" CODEX_SYSTEM_BUNDLE_ROOT="$CODEX_EMPTY_APPS" \
  DEPLOYED_ARTIFACTS_LOG="$C12_LOG" "$DEPLOY_BASH" "$C12_REPO/deployment/deployment.sh" \
  --global --type style --target codex --clear-backups 2>&1)"
c12_plain="$(printf '%s\n' "$c12_out" | codex_plain)"
assert_eq "$(printf '%s\n' "$c12_plain" | grep -c 'generated' || true)" "1" \
  "two style files must produce exactly one generated file"
assert_eq "$(printf '%s\n' "$c12_plain" | grep -c 'merged' || true)" "1" \
  "two style files must produce exactly one configuration merge"
printf '%s\n' "$c12_plain" | grep -q "active style for codex is 'natural-language'" ||
  fail "the non-active style file must draw a skip message"
[[ ! -e "${C12_HOME}/.codex/instructions/other-style.md" ]] ||
  fail "the non-active style file must write no generated file"
assert_eq "$(grep -cF "${C12_HOME}/.codex/instructions/natural-language.md"$'\t' "$C12_LOG" || true)" "1" \
  "two style files must log exactly one generated file"

# --- Project scope is rejected for the Codex style ---
C13_HOME="${CODEX_SCRATCH}/c13-home"
C13_PROJECT="${CODEX_SCRATCH}/c13-project"
C13_LOG="${CODEX_SCRATCH}/c13.log"
seed_codex_home "$C13_HOME" "gpt-test"
mkdir -p "$C13_PROJECT"
c13_out="$(codex_run "$C13_HOME" "$C13_LOG" "$CODEX_EMPTY_APPS" --project-dir "$C13_PROJECT" --type style --target codex 2>&1)"
c13_plain="$(printf '%s\n' "$c13_out" | codex_plain)"
printf '%s\n' "$c13_plain" | grep -q 'rejected for project scope' ||
  fail "project-scope Codex style deployment must be rejected with a message"
[[ ! -e "${C13_PROJECT}/.codex/instructions/natural-language.md" ]] ||
  fail "project-scope Codex style deployment must write no generated file"
[[ ! -e "${C13_PROJECT}/.codex/config.toml" ]] ||
  fail "project-scope Codex style deployment must write no configuration key"

printf 'Style deployment regression passed\n'
