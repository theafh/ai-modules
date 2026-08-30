#!/usr/bin/env bash
# Regression coverage for the style artefact type, Claude two-placement
# deploy, and merge_json_key prior-value capture/restore.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
DEPLOY_LOG="${REPO_ROOT}/deployment/deployed_artefacts.log"
STYLE_SRC="${REPO_ROOT}/styles/natural-language.md"
SCRATCH="$(mktemp -d)"
LOG_BACKUP="${SCRATCH}/deployed_artefacts.log.backup"
LOG_HAD_FILE=false

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
  if [[ "$LOG_HAD_FILE" == true ]]; then
    mv "$LOG_BACKUP" "$DEPLOY_LOG"
  else
    rm -f "$DEPLOY_LOG"
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

cd "$REPO_ROOT"

if [[ -f "$DEPLOY_LOG" ]]; then
  LOG_HAD_FILE=true
  cp "$DEPLOY_LOG" "$LOG_BACKUP"
fi
rm -f "$DEPLOY_LOG"

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

help_out="$("$DEPLOY_SCRIPT" --help)"
printf '%s\n' "$help_out" | grep -q 'style' || fail "--help does not list style type"
grep -q 'STYLE_MAP\|style:<name>' "$DEPLOY_SCRIPT" || true
grep -q 'declare -A STYLE_MAP' "$DEPLOY_SCRIPT" || fail "STYLE_MAP not declared"
grep -n 'merge_json_key()' -A80 "$DEPLOY_SCRIPT" | grep -q 'lookup_logged_prior\|@absent' ||
  fail "first-write prior recording must live inside merge_json_key"

# --- Scratch trees ---
HOME_DIR="${SCRATCH}/home"
PROJECT_DIR="${SCRATCH}/project"
mkdir -p "$HOME_DIR" "$PROJECT_DIR"
# Pre-seed a home settings value that project-dir deploy must not touch
mkdir -p "$HOME_DIR/.claude"
printf '%s\n' '{"outputStyle":"home-prior"}' > "$HOME_DIR/.claude/settings.json"

# --- Global dry-run: two actions, resolved under scratch HOME ---
global_dry="$(HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --global --type style --target claude --dry-run)"
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
project_dry="$(HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --dry-run)"
printf '%s\n' "$project_dry" | grep -q "${PROJECT_DIR}/.claude/output-styles/natural-language.md" ||
  fail "project dry-run missing style file copy"
printf '%s\n' "$project_dry" | grep -q "${PROJECT_DIR}/.claude/settings.json" ||
  fail "project dry-run missing settings merge"
if printf '%s\n' "$project_dry" | grep -q "${HOME_DIR}/.claude/"; then
  fail "project dry-run must not resolve paths under HOME"
fi

# --- Real project-dir deploy ---
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
assert_file "$PROJECT_DIR/.claude/output-styles/natural-language.md"
cmp -s "$STYLE_SRC" "$PROJECT_DIR/.claude/output-styles/natural-language.md" ||
  fail "project deploy style file not byte-identical to repo source"
jq -e '.outputStyle == "natural-language"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "project deploy did not set outputStyle to conf style name"
jq -e '.outputStyle == "home-prior"' "$HOME_DIR/.claude/settings.json" >/dev/null ||
  fail "project deploy mutated home settings"

# --- Redeploy: single log entry per artefact, same settings value ---
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
file_log_count="$(grep -cF "${PROJECT_DIR}/.claude/output-styles/natural-language.md"$'\t' "$DEPLOY_LOG" || true)"
key_log_count="$(grep -cF "${PROJECT_DIR}/.claude/settings.json[outputStyle]"$'\t' "$DEPLOY_LOG" || true)"
assert_eq "$file_log_count" "1" "expected one log line for style file after redeploy"
assert_eq "$key_log_count" "1" "expected one log line for outputStyle after redeploy"
jq -e '.outputStyle == "natural-language"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "redeploy changed outputStyle"

# --- Project uninstall restores @absent (no prior key) ---
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --uninstall >/dev/null
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
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
jq -e '.outputStyle == "natural-language"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "deploy with prior did not set natural-language"
# Second deploy must keep first prior (Explanatory), not the live natural-language
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
prior_field="$(awk -F'\t' -v p="${PROJECT_DIR}/.claude/settings.json[outputStyle]" '$1==p{print $5; exit}' "$DEPLOY_LOG")"
assert_eq "$prior_field" '"Explanatory"' "first-write prior must stay Explanatory across redeploy"
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --uninstall >/dev/null
jq -e '.outputStyle == "Explanatory"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "uninstall did not restore original Explanatory prior"
if grep -qF "${PROJECT_DIR}/.claude/settings.json[outputStyle]" "$DEPLOY_LOG" 2>/dev/null; then
  fail "uninstall left settings path[key] after prior restore"
fi

# --- Single-deploy then uninstall restores prior (scalar path) ---
printf '%s\n' '{"outputStyle":"Learning"}' > "$PROJECT_DIR/.claude/settings.json"
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude >/dev/null
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --type style --target claude --uninstall >/dev/null
jq -e '.outputStyle == "Learning"' "$PROJECT_DIR/.claude/settings.json" >/dev/null ||
  fail "uninstall did not restore Learning prior"

# --- Global real deploy into scratch HOME ---
rm -f "$DEPLOY_LOG"
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --global --type style --target claude --clear-backups >/dev/null
assert_file "$HOME_DIR/.claude/output-styles/natural-language.md"
cmp -s "$STYLE_SRC" "$HOME_DIR/.claude/output-styles/natural-language.md" ||
  fail "global deploy style file not byte-identical"
jq -e '.outputStyle == "natural-language"' "$HOME_DIR/.claude/settings.json" >/dev/null ||
  fail "global deploy did not set outputStyle"
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --global --type style --target claude --uninstall >/dev/null

# --- Legacy four-field path[key] still strips ---
rm -f "$DEPLOY_LOG"
legacy_settings="${SCRATCH}/legacy-settings.json"
printf '%s\n' '{"outputStyle":"keep-me","hooks":{}}' > "$legacy_settings"
printf '%s\t%s\t%s\t%s\n' \
  "${legacy_settings}[outputStyle]" "claude" "style" "styles/natural-language.md" \
  > "$DEPLOY_LOG"
dry_legacy="$(HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --uninstall --type style --target claude --dry-run)"
printf '%s\n' "$dry_legacy" | grep -q 'would-strip' ||
  fail "legacy four-field dry-run should report strip without fifth field"
# Restore log for real uninstall (dry-run keeps entries)
printf '%s\t%s\t%s\t%s\n' \
  "${legacy_settings}[outputStyle]" "claude" "style" "styles/natural-language.md" \
  > "$DEPLOY_LOG"
HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --uninstall --type style --target claude >/dev/null
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

# parse_deployment_conf recognizes style: via STYLE_MAP
# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  parse_deployment_conf
  [[ "${STYLE_MAP[claude]:-}" == "natural-language" ]] ||
    fail "STYLE_MAP[claude] should be natural-language from deployment.conf"
)

printf 'Style deployment regression passed\n'
