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
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
# Invoke the deploy script on the stock bash the floor targets.
DEPLOY_BASH="/bin/bash"
STYLE_SRC="${REPO_ROOT}/styles/natural-language.md"
SCRATCH="$(mktemp -d)"
# Every deploy here writes a scratch log, never the machine-wide manifest.
DEPLOY_LOG="${SCRATCH}/deployed.log"
CONF_TEMPLATE="${REPO_ROOT}/deployment/ai_asset_deploy.conf.template"

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

# --- Output-style shadow reporting and the global override caveat ---
# The global scenarios stage this checkout's own .claude settings files, the
# way the harness backs aside the fixtures it stages, and restore them on exit
# so the working tree is left byte-identical.
REPO_CLAUDE_DIR="${REPO_ROOT}/.claude"
REPO_SETTINGS_LOCAL="${REPO_CLAUDE_DIR}/settings.local.json"
REPO_SETTINGS="${REPO_CLAUDE_DIR}/settings.json"
REPO_SETTINGS_LOCAL_SAVED="${SCRATCH}/repo-settings.local.json"
REPO_SETTINGS_SAVED="${SCRATCH}/repo-settings.json"
REPO_CLAUDE_DIR_EXISTED=false
REPO_SETTINGS_LOCAL_EXISTED=false
REPO_SETTINGS_EXISTED=false

if [[ -d "$REPO_CLAUDE_DIR" ]]; then
  REPO_CLAUDE_DIR_EXISTED=true
fi
if [[ -f "$REPO_SETTINGS_LOCAL" ]]; then
  REPO_SETTINGS_LOCAL_EXISTED=true
  cp "$REPO_SETTINGS_LOCAL" "$REPO_SETTINGS_LOCAL_SAVED"
fi
if [[ -f "$REPO_SETTINGS" ]]; then
  REPO_SETTINGS_EXISTED=true
  cp "$REPO_SETTINGS" "$REPO_SETTINGS_SAVED"
fi

restore_repo_settings() {
  if [[ "$REPO_SETTINGS_LOCAL_EXISTED" == true ]]; then
    cp "$REPO_SETTINGS_LOCAL_SAVED" "$REPO_SETTINGS_LOCAL"
  else
    rm -f "$REPO_SETTINGS_LOCAL"
  fi
  if [[ "$REPO_SETTINGS_EXISTED" == true ]]; then
    cp "$REPO_SETTINGS_SAVED" "$REPO_SETTINGS"
  else
    rm -f "$REPO_SETTINGS"
  fi
  if [[ "$REPO_CLAUDE_DIR_EXISTED" == false ]]; then
    rmdir "$REPO_CLAUDE_DIR" 2>/dev/null || true
  fi
}
trap 'restore_repo_settings; cleanup' EXIT

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

# Leave the checkout as found before the harness exits.
restore_repo_settings

printf 'Style deployment regression passed\n'
