#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# deployment.sh — deploy repo artifacts into global config dirs
#                 for VS Code GitHub Copilot, Cursor, Claude Code,
#                 OpenAI Codex, Google Antigravity, and OpenCode
#
# Discovery uses two roots: plugins/<plugin>/<asset-folder>/ where the
# asset-folder name determines the artifact type (agents/, commands/,
# skills/, hooks/), and repo-root styles/ for the style type (each
# top-level *.md file). Hidden files and README files are always
# excluded from discovery.
#
# Per-tool deployment configuration is loaded from deployment.conf
# (robots.txt-style). Current directives:
#   #tool                     Section heading
#   disallow:path             Relative path to exclude for that tool
#   replace:path VAR=value    Replace $VAR$ in matching deployed copies
#   style:<name>              Active output-style name for that tool
#
# Features:
#   --global         Deploy into global config dirs (explicit mode)
#   --type TYPES     Filter by artifact type (command,skill,agent,hook,style)
#   --target TARGETS Filter by deploy target (vscode,claude,cursor,codex,antigravity,opencode)
#   --project-dir D  Deploy into a project directory instead of global config dirs
#   --dry-run        Preview changes without applying them
#   --uninstall      Remove previously deployed artifacts from deployed_artefacts.log
#   --clear-backups  Remove old selected backups before creating new ones
#   Logs deployed artifacts to deployed_artefacts.log with target/source metadata
#   Backs up only activated targets (disabled in project-dir mode).
#   Backups land in $HOME as <name>_<timestamp>, where <name> defaults to
#   basename(target_dir). The caller can override <name> when the basename
#   isn't tool-distinctive — e.g. VS Code's user-prompts dir on macOS and
#   OpenCode's ~/.config/opencode config dir both have generic basenames.
#
# Usage:
#   ./deployment.sh                              # show usage and examples
#   ./deployment.sh --global                     # autodiscover all in global config dirs
#   ./deployment.sh --global --clear-backups     # drop old backups, then create fresh ones
#   ./deployment.sh --uninstall                  # uninstall logged artifacts only
#   ./deployment.sh --clear-backups --target cursor,claude
#                                                 # clear managed backups only
#   ./deployment.sh --global --type skill,command
#                                                 # deploy only skills+commands globally
#   ./deployment.sh --global --target vscode,claude
#                                                 # deploy only to vscode+claude globally
#   ./deployment.sh --project-dir /path/to/repo  # deploy into a single project
#   ./deployment.sh --global --dry-run           # preview global deployment
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DRY_RUN=false
UNINSTALL=false
CLEAR_BACKUPS=false
GLOBAL_MODE=false
BACKUP_CLEANUP_ONLY=false
NO_SCOPE_UNINSTALL=false
TYPE_FILTER=""
TARGET_FILTER=""
PROJECT_DIR=""
ORIGINAL_ARGC=$#

print_usage() {
  cat <<'USAGE'
Usage: deployment.sh [OPTIONS]

Run with no arguments to see this help. To deploy to global config directories,
pass --global explicitly.

Options:
  --global          Deploy into global config dirs. This is the previous default
                    behavior of running the script with no arguments.
  --type TYPES      Comma-separated artifact types to deploy: command,skill,agent,hook,style.
                    Requires --global or --project-dir unless used with --uninstall.
  --target TARGETS  Comma-separated deploy targets: vscode,claude,cursor,codex,antigravity,opencode
  --project-dir DIR Deploy into a project directory instead of global config dirs.
                    Backups are disabled in this mode.
  --uninstall       Uninstall mode; remove matching logged deployed artifacts after backup.
                    Can run without --global or --project-dir.
  --clear-backups   Remove old backups for selected targets before creating new backups.
                    Without --global or --project-dir, clears backups and exits.
  --dry-run         Preview changes without applying them
  -h, --help        Show this help message

Examples:
  ./deployment/deployment.sh
  ./deployment/deployment.sh --global
  ./deployment/deployment.sh --global --dry-run
  ./deployment/deployment.sh --global --target codex
  ./deployment/deployment.sh --project-dir /path/to/repo --target claude
  ./deployment/deployment.sh --uninstall
  ./deployment/deployment.sh --clear-backups --target cursor,claude
USAGE
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      GLOBAL_MODE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    --clear-backups)
      CLEAR_BACKUPS=true
      shift
      ;;
    --type)
      TYPE_FILTER="$2"
      shift 2
      ;;
    --target)
      TARGET_FILTER="$2"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$ORIGINAL_ARGC" -eq 0 ]]; then
  print_usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME}"

if [[ "$GLOBAL_MODE" == true && -n "$PROJECT_DIR" ]]; then
  echo "Error: --global and --project-dir cannot be used together." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Asset folders — folder name determines artifact type.
# Declared here (before REPO_ROOT discovery) so root auto-discovery can use
# the same folder list as artifact discovery below.
# ---------------------------------------------------------------------------
declare -A ASSET_FOLDERS=(
  [agents]="agent"
  [commands]="command"
  [skills]="skill"
  [hooks]="hook"
)

# ---------------------------------------------------------------------------
# Discover REPO_ROOT by walking up from SCRIPT_DIR until we find a directory
# that contains a plugins/ folder. Artifacts live under
# plugins/<plugin>/<asset-folder>/. Keeps the script location-independent.
# ---------------------------------------------------------------------------
REPO_ROOT="$SCRIPT_DIR"
while [[ "$REPO_ROOT" != "/" ]]; do
  if [[ -d "$REPO_ROOT/plugins" ]]; then
    break
  fi
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

if [[ "$REPO_ROOT" == "/" ]]; then
  echo "Error: could not locate repo root from $SCRIPT_DIR — no plugins/ folder found in any ancestor." >&2
  exit 1
fi

PLUGINS_ROOT="${REPO_ROOT}/plugins"
STYLES_ROOT="${REPO_ROOT}/styles"

# ---------------------------------------------------------------------------
# Project-dir mode — validate and resolve
# ---------------------------------------------------------------------------
if [[ -n "$PROJECT_DIR" ]]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
    echo "Error: --project-dir path does not exist: $PROJECT_DIR" >&2
    exit 1
  }
  if [[ "$CLEAR_BACKUPS" == true ]]; then
    echo "  Note: --clear-backups has no effect in project-dir mode (backups are disabled)" >&2
    CLEAR_BACKUPS=false
  fi
fi

# ---------------------------------------------------------------------------
# Target directories
# When --project-dir is set, targets point inside the project directory
# using each IDE's native project-level config path convention.
# ---------------------------------------------------------------------------
if [[ -n "$PROJECT_DIR" ]]; then
  CLAUDE_DIR="${PROJECT_DIR}/.claude"
  CURSOR_DIR="${PROJECT_DIR}/.cursor"
  CODEX_DIR="${PROJECT_DIR}/.codex"
  CODEX_SKILLS_DIR="${PROJECT_DIR}/.agents/skills"
  VSCODE_COPILOT_DIR="${PROJECT_DIR}/.github"
  VSCODE_PROMPTS_DIR="${PROJECT_DIR}/.github/prompts"
  OPENCODE_DIR="${PROJECT_DIR}/.opencode"
  # Antigravity's native project-level convention is the workspace .agents/ tree.
  ANTIGRAVITY_TREE_DIR="${PROJECT_DIR}/.agents"
  ANTIGRAVITY_DIR="${PROJECT_DIR}/.agents"
else
  CLAUDE_DIR="${HOME_DIR}/.claude"
  CURSOR_DIR="${HOME_DIR}/.cursor"
  CODEX_DIR="${HOME_DIR}/.codex"
  CODEX_SKILLS_DIR=""
  VSCODE_COPILOT_DIR="${HOME_DIR}/.copilot"
  OPENCODE_DIR="${HOME_DIR}/.config/opencode"
  ANTIGRAVITY_TREE_DIR="${HOME_DIR}/.gemini"
  ANTIGRAVITY_DIR="${ANTIGRAVITY_TREE_DIR}/config"
  if [[ "$OSTYPE" == darwin* ]]; then
    VSCODE_PROMPTS_DIR="${HOME_DIR}/Library/Application Support/Code/User/prompts"
  elif [[ "$OSTYPE" == linux* ]]; then
    VSCODE_PROMPTS_DIR="${HOME_DIR}/.config/Code/User/prompts"
  else
    VSCODE_PROMPTS_DIR="${HOME_DIR}/.config/Code/User/prompts"
  fi
fi

# Dormant managed-global-rules feature, parked to keep its exact strings and
# intent on record: these five inputs once fed a routine that wrote a
# <!-- BEGIN/END GLOBAL RULES --> block into each tool's instruction file.
# To revive, re-enable these declarations and restore the routine that writes
# the marker-delimited block into each instruction file.
# CLAUDE_MD="${CLAUDE_DIR}/CLAUDE.md"
# AGENTS_MD="${CODEX_DIR}/AGENTS.md"
# ANTIGRAVITY_RULES_MD="${ANTIGRAVITY_TREE_DIR}/GEMINI.md"
# MARKER_BEGIN="<!-- BEGIN GLOBAL RULES -->"
# MARKER_END="<!-- END GLOBAL RULES -->"
DEPLOYED_ARTIFACTS_LOG="${SCRIPT_DIR}/deployed_artefacts.log"
DEPLOYMENT_CONF="${SCRIPT_DIR}/deployment.conf"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf "  \033[34m%-10s\033[0m %s\n" "$1" "$2"; }
ok()    { printf "  \033[32m%-10s\033[0m %s\n" "$1" "$2"; }
warn()  { printf "  \033[33m%-10s\033[0m %s\n" "$1" "$2"; }
err()   { printf "  \033[31m%-10s\033[0m %s\n" "$1" "$2"; }

SUMMARY_BACKUPS=0
SUMMARY_CLEARED_BACKUPS=0
SUMMARY_DEPLOY_ACTIONS=0
SUMMARY_UNINSTALL_ACTIONS=0
SUMMARY_RULE_UPDATES=0

print_summary() {
  local summary_parts=()
  summary_parts+=("${SUMMARY_BACKUPS} backup(s)")
  summary_parts+=("${SUMMARY_CLEARED_BACKUPS} old backup(s) removed")
  summary_parts+=("${SUMMARY_DEPLOY_ACTIONS} deploy action(s)")
  summary_parts+=("${SUMMARY_UNINSTALL_ACTIONS} uninstall action(s)")
  summary_parts+=("${SUMMARY_RULE_UPDATES} instruction update(s)")

  local summary_text
  summary_text="$(printf '%s, ' "${summary_parts[@]}")"
  summary_text="${summary_text%, }"

  if $DRY_RUN; then
    info "summary" "DRY RUN simulated: ${summary_text}"
  else
    ok "summary" "Performed: ${summary_text}"
  fi
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    if $DRY_RUN; then
      info "would-mk" "$dir"
    else
      mkdir -p "$dir"
      ok "created" "$dir"
    fi
  fi
}

append_deployed_artifact_log() {
  local deployed_path="${1:-}"
  local target_id="${2:-}"
  local artifact_type="${3:-}"
  local source_path="${4:-}"
  local prior_value="${5:-}"
  $DRY_RUN && return 0
  [[ -n "$deployed_path" && -n "$target_id" && -n "$artifact_type" && -n "$source_path" ]] || return 0
  if [[ -n "$prior_value" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$deployed_path" "$target_id" "$artifact_type" "$source_path" "$prior_value" >> "$DEPLOYED_ARTIFACTS_LOG"
  else
    printf '%s\t%s\t%s\t%s\n' "$deployed_path" "$target_id" "$artifact_type" "$source_path" >> "$DEPLOYED_ARTIFACTS_LOG"
  fi
}

# Look up a previously recorded prior for a path[key] log destination.
# Prints the prior (compact JSON or @absent) and returns 0 when found.
lookup_logged_prior() {
  local log_path="$1"
  [[ -f "$DEPLOYED_ARTIFACTS_LOG" ]] || return 1

  local logged_path="" logged_target_id="" logged_type="" logged_source="" logged_prior=""
  while IFS=$'\t' read -r logged_path logged_target_id logged_type logged_source logged_prior || [[ -n "$logged_path" ]]; do
    [[ -n "$logged_path" ]] || continue
    if [[ "$logged_path" == "$log_path" && -n "$logged_prior" ]]; then
      printf '%s' "$logged_prior"
      return 0
    fi
  done < "$DEPLOYED_ARTIFACTS_LOG"
  return 1
}

dedupe_deployed_artifact_log() {
  $DRY_RUN && return 0
  [[ -f "$DEPLOYED_ARTIFACTS_LOG" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  sort -u "$DEPLOYED_ARTIFACTS_LOG" > "$tmp"
  mv "$tmp" "$DEPLOYED_ARTIFACTS_LOG"
}

trap dedupe_deployed_artifact_log EXIT

path_exists() {
  local path="$1"

  # Handle path[key] notation — check the JSON file exists and contains the key
  if [[ "$path" =~ ^(.+)\[([a-zA-Z_][a-zA-Z0-9_]*)\]$ ]]; then
    local json_file="${BASH_REMATCH[1]}"
    local json_key="${BASH_REMATCH[2]}"
    [[ -f "$json_file" ]] && jq -e ".${json_key}" "$json_file" &>/dev/null
    return $?
  fi

  [[ -e "$path" || -L "$path" ]]
}

# ---------------------------------------------------------------------------
# Filter helpers
# ---------------------------------------------------------------------------

# Check if a value is in a comma-separated filter string.
# Returns 0 (true) when the filter is empty (accept all) or the value matches.
matches_filter() {
  local value="$1"
  local filter="$2"

  [[ -z "$filter" ]] && return 0

  local IFS=','
  for item in $filter; do
    item="${item// /}"
    [[ "$item" == "$value" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# deployment.conf parser
#
# Parses per-tool deployment configuration and populates:
#   DISALLOW_MAP["tool|rel_path"] = 1
#   REPLACE_RULES+=("tool<TAB>pattern<TAB>var<TAB>value")
#   STYLE_MAP["tool"] = name
# ---------------------------------------------------------------------------
declare -A DISALLOW_MAP=()
declare -A STYLE_MAP=()
declare -a REPLACE_RULES=()

path_matches_pattern() {
  local rel_path="$1"
  local pattern="$2"

  [[ "$rel_path" == "$pattern" ]] && return 0

  # Treat a trailing slash as a subtree match so rules like agents/ apply to
  # every asset under that directory.
  if [[ "$pattern" == */ && "$rel_path" == "$pattern"* ]]; then
    return 0
  fi

  # shellcheck disable=SC2254
  case "$rel_path" in
    $pattern) return 0 ;;
  esac

  return 1
}

parse_deployment_conf() {
  [[ -f "$DEPLOYMENT_CONF" ]] || return 0

  local current_tool=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip empty lines and comments (but not section headings)
    [[ -z "$line" ]] && continue
    [[ "$line" == \#\#* ]] && continue  # skip ## double-hash comments

    # Section heading: #tool
    if [[ "$line" =~ ^#([a-zA-Z_][a-zA-Z0-9_-]*)$ ]]; then
      current_tool="${BASH_REMATCH[1]}"
      continue
    fi

    # Disallow directive
    if [[ -n "$current_tool" && "$line" =~ ^disallow:(.+)$ ]]; then
      local disallowed="${BASH_REMATCH[1]}"
      # Strip leading/trailing whitespace
      disallowed="${disallowed#"${disallowed%%[![:space:]]*}"}"
      disallowed="${disallowed%"${disallowed##*[![:space:]]}"}"
      [[ -n "$disallowed" ]] && DISALLOW_MAP["${current_tool}|${disallowed}"]=1
      continue
    fi

    # Replace directive
    if [[ -n "$current_tool" && "$line" =~ ^replace:([^[:space:]]+)[[:space:]]+([^=[:space:]]+)=(.*)$ ]]; then
      local replace_path="${BASH_REMATCH[1]}"
      local replace_var="${BASH_REMATCH[2]}"
      local replace_value="${BASH_REMATCH[3]}"

      replace_path="${replace_path#"${replace_path%%[![:space:]]*}"}"
      replace_path="${replace_path%"${replace_path##*[![:space:]]}"}"
      replace_value="${replace_value#"${replace_value%%[![:space:]]*}"}"

      if [[ -n "$replace_path" && -n "$replace_var" ]]; then
        REPLACE_RULES+=("${current_tool}"$'\t'"${replace_path}"$'\t'"${replace_var}"$'\t'"${replace_value}")
      fi
      continue
    fi

    # Style directive — active output-style name for this tool
    if [[ -n "$current_tool" && "$line" =~ ^style:(.+)$ ]]; then
      local style_name="${BASH_REMATCH[1]}"
      style_name="${style_name#"${style_name%%[![:space:]]*}"}"
      style_name="${style_name%"${style_name##*[![:space:]]}"}"
      [[ -n "$style_name" ]] && STYLE_MAP["$current_tool"]="$style_name"
      continue
    fi
  done < "$DEPLOYMENT_CONF"
}

# Check if a relative path is disallowed for a given tool.
# Supports exact match and glob patterns with * and **.
is_disallowed() {
  local tool="$1"
  local rel_path="$2"

  # Exact match
  [[ -n "${DISALLOW_MAP["${tool}|${rel_path}"]+x}" ]] && return 0

  # Check configured patterns.
  for key in "${!DISALLOW_MAP[@]}"; do
    local key_tool="${key%%|*}"
    local key_pattern="${key#*|}"
    [[ "$key_tool" == "$tool" ]] || continue

    # Skip exact matches (already handled)
    [[ "$key_pattern" == "$rel_path" ]] && continue

    path_matches_pattern "$rel_path" "$key_pattern" && return 0
  done

  return 1
}

get_matching_replacements() {
  local tool="$1"
  local rel_path="$2"
  local rule=""

  for rule in "${REPLACE_RULES[@]}"; do
    local rule_tool=""
    local rule_pattern=""
    local rule_var=""
    local rule_value=""
    IFS=$'\t' read -r rule_tool rule_pattern rule_var rule_value <<< "$rule"

    [[ "$rule_tool" == "$tool" ]] || continue
    path_matches_pattern "$rel_path" "$rule_pattern" || continue

    printf '%s=%s\n' "$rule_var" "$rule_value"
  done
}

# ---------------------------------------------------------------------------
# Validate flags
# ---------------------------------------------------------------------------
VALID_TYPES="command,skill,agent,hook,style"
VALID_TARGETS="vscode,claude,cursor,codex,antigravity,opencode"

if [[ -n "$TYPE_FILTER" ]]; then
  IFS=',' read -ra _type_items <<< "$TYPE_FILTER"
  for _t in "${_type_items[@]}"; do
    _t="${_t// /}"
    if ! matches_filter "$_t" "$VALID_TYPES"; then
      err "abort" "Unknown artifact type '${_t}' in --type (valid: ${VALID_TYPES})"
      exit 1
    fi
  done
  unset _type_items _t
fi

if [[ -n "$TARGET_FILTER" ]]; then
  IFS=',' read -ra _target_items <<< "$TARGET_FILTER"
  for _tgt in "${_target_items[@]}"; do
    _tgt="${_tgt// /}"
    if [[ "$_tgt" == "gemini" ]]; then
      err "abort" "Gemini CLI support is retired because Google is removing that app and porting it to Antigravity; use --target antigravity instead."
      exit 1
    fi
    if ! matches_filter "$_tgt" "$VALID_TARGETS"; then
      err "abort" "Unknown deploy target '${_tgt}' in --target (valid: ${VALID_TARGETS})"
      exit 1
    fi
  done
  unset _target_items _tgt
fi

if [[ "$GLOBAL_MODE" != true && -z "$PROJECT_DIR" ]]; then
  if [[ "$UNINSTALL" == true ]]; then
    # Log-driven uninstall is a maintenance mode: it uses the deployment log
    # plus filters, not a newly selected deployment scope.
    NO_SCOPE_UNINSTALL=true
  elif [[ "$CLEAR_BACKUPS" == true && -z "$TYPE_FILTER" ]]; then
    # Backup cleanup is the other no-scope maintenance mode. --target narrows
    # backup roots; --type remains a deploy/uninstall artifact filter.
    BACKUP_CLEANUP_ONLY=true
  else
    echo "Error: deployment requires an explicit scope. Pass --global or --project-dir DIR." >&2
    print_usage >&2
    exit 1
  fi
fi

# jq is required for JSON-merge hook deployment (Claude Code settings.json)
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# App targets: id|label|base_dir
# ---------------------------------------------------------------------------
ALL_APP_TARGETS=(
  "vscode|VS Code|${VSCODE_COPILOT_DIR}"
  "cursor|Cursor|${CURSOR_DIR}"
  "claude|Claude Code|${CLAUDE_DIR}"
  "codex|OpenAI Codex|${CODEX_DIR}"
  "antigravity|Antigravity|${ANTIGRAVITY_DIR}"
  "opencode|OpenCode|${OPENCODE_DIR}"
)

# Build filtered target list. In project-dir mode, every remaining target has
# a configured project-level path; an empty path is a configuration error.
APP_TARGETS=()
for target in "${ALL_APP_TARGETS[@]}"; do
  IFS='|' read -r app_id app_label _dir <<< "$target"
  matches_filter "$app_id" "$TARGET_FILTER" || continue

  if [[ -n "$PROJECT_DIR" && -z "$_dir" ]]; then
    warn "skip" "${app_label} has no project-level config convention — skipped in project-dir mode (needs research)"
    continue
  fi

  APP_TARGETS+=("$target")
done

if [[ ${#APP_TARGETS[@]} -eq 0 ]]; then
  err "abort" "No matching targets for --target '${TARGET_FILTER}'"
  exit 1
fi

logged_path_matches_active_targets() {
  local target_id="$1"
  local target

  for target in "${APP_TARGETS[@]}"; do
    local active_target_id _label _base_dir
    IFS='|' read -r active_target_id _label _base_dir <<< "$target"
    [[ "$active_target_id" == "$target_id" ]] && return 0
  done

  return 1
}

target_is_active() {
  local target_id="$1"
  local target

  for target in "${APP_TARGETS[@]}"; do
    local active_target_id _label _base_dir
    IFS='|' read -r active_target_id _label _base_dir <<< "$target"
    [[ "$active_target_id" == "$target_id" ]] && return 0
  done

  return 1
}

# ---------------------------------------------------------------------------
# Autodiscovery from two roots
#
# 1. plugins/<plugin>/<asset-folder>/ where the asset-folder name
#    (agents/, commands/, skills/, hooks/) determines the artifact type.
#    For skills: each subdirectory containing SKILL.md is one skill artifact.
#    For others: each file in the folder is one artifact.
# 2. repo-root styles/ — each top-level *.md file is one style artifact.
# ---------------------------------------------------------------------------
discover_artifacts() {
  local discovered=()

  if [[ -d "$PLUGINS_ROOT" ]]; then
    for plugin_dir in "$PLUGINS_ROOT"/*/; do
      [[ -d "$plugin_dir" ]] || continue
      local plugin_name
      plugin_name="$(basename "$plugin_dir")"

      for folder in "${!ASSET_FOLDERS[@]}"; do
        local art_type="${ASSET_FOLDERS[$folder]}"
        local folder_path="${plugin_dir}${folder}"

        # Skip if folder doesn't exist
        [[ -d "$folder_path" ]] || continue

        # Skip if type doesn't match filter
        matches_filter "$art_type" "$TYPE_FILTER" || continue

        if [[ "$art_type" == "skill" ]]; then
          # Skills: each subdirectory with SKILL.md is an artifact
          for skill_dir in "$folder_path"/*/; do
            [[ -d "$skill_dir" ]] || continue
            [[ -f "${skill_dir}SKILL.md" ]] || continue
            local skill_name
            skill_name="$(basename "$skill_dir")"
            local rel_path="plugins/${plugin_name}/${folder}/${skill_name}"
            discovered+=("${skill_name}|${art_type}|${rel_path}")
          done
        else
          # Agents, commands, hooks: each file is an artifact
          for f in "$folder_path"/*; do
            [[ -f "$f" ]] || continue
            local bname
            bname="$(basename "$f")"
            # Skip hidden files and README files
            [[ "$bname" == .* ]] && continue
            [[ "${bname^^}" == README* ]] && continue
            local name_no_ext="${bname%.*}"
            local rel_path="plugins/${plugin_name}/${folder}/${bname}"
            discovered+=("${name_no_ext}|${art_type}|${rel_path}")
          done
        fi
      done
    done
  fi

  # Repo-root styles/ — second discovery root for the style type
  if matches_filter "style" "$TYPE_FILTER" && [[ -d "$STYLES_ROOT" ]]; then
    local style_file
    for style_file in "$STYLES_ROOT"/*.md; do
      [[ -f "$style_file" ]] || continue
      local bname
      bname="$(basename "$style_file")"
      [[ "$bname" == .* ]] && continue
      [[ "${bname^^}" == README* ]] && continue
      local name_no_ext="${bname%.*}"
      local rel_path="styles/${bname}"
      discovered+=("${name_no_ext}|style|${rel_path}")
    done
  fi

  if [[ ${#discovered[@]} -gt 0 ]]; then
    printf '%s\n' "${discovered[@]}"
  fi
}

# ---------------------------------------------------------------------------
# Copy a file into a deployment target.
# ---------------------------------------------------------------------------
copy_file() {
  local source="$1"
  local target="$2"
  local target_id="$3"
  local artifact_type="$4"

  if [[ ! -f "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  if $DRY_RUN; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    info "would-copy" "$target <- $source"
    return 0
  fi

  if [[ -L "$target" || -f "$target" ]]; then rm "$target"; fi

  cp "$source" "$target"
  ok "copied" "$target <- $source"
  SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  append_deployed_artifact_log "$target" "$target_id" "$artifact_type" "$source"
}

apply_replacements_to_file() {
  local file="$1"
  shift

  [[ -f "$file" ]] || return 0

  if [[ -s "$file" ]] && ! grep -Iq . "$file" 2>/dev/null; then
    return 0
  fi

  local spec=""
  for spec in "$@"; do
    local variable_name="${spec%%=*}"
    local replacement_value="${spec#*=}"
    local placeholder="\$${variable_name}\$"

    PLACEHOLDER="$placeholder" REPLACEMENT_VALUE="$replacement_value" \
      perl -0pi -e 'my $placeholder = $ENV{PLACEHOLDER}; my $replacement_value = $ENV{REPLACEMENT_VALUE}; s/\Q$placeholder\E/$replacement_value/g;' "$file"
  done
}

apply_replacements_to_path() {
  local target="$1"
  shift

  [[ $# -gt 0 ]] || return 0

  if [[ -f "$target" ]]; then
    apply_replacements_to_file "$target" "$@"
    return 0
  fi

  if [[ -d "$target" ]]; then
    local file=""
    while IFS= read -r -d '' file; do
      apply_replacements_to_file "$file" "$@"
    done < <(find "$target" -type f -print0)
  fi
}

maybe_apply_replacements() {
  local target="$1"
  shift

  [[ $# -gt 0 ]] || return 0

  if $DRY_RUN; then
    info "would-sub" "$target ($# replacement(s))"
    return 0
  fi

  apply_replacements_to_path "$target" "$@"
  ok "replaced" "$target"
}

# ---------------------------------------------------------------------------
# Strip Python bytecode from a freshly copied destination directory.
#
# A directory source is copied wholesale with `cp -R`, and BSD cp offers no
# exclude flag, so gitignored bytecode left behind by running a skill's
# bundled Python scripts travels into every deployment target. Prune it off
# the destination instead of filtering the copy: __pycache__ trees first,
# then any stray .pyc sitting outside one. `find` plus `rm` keeps this
# dependency-free rather than pulling in a copy tool with an exclude flag.
# ---------------------------------------------------------------------------
prune_python_bytecode() {
  local target="$1"

  [[ -d "$target" ]] || return 0

  find "$target" -type d -name '__pycache__' -prune -exec rm -rf {} +
  find "$target" -type f -name '*.pyc' -exec rm -f {} +
}

copy_path_with_replacements() {
  local source="$1"
  local target="$2"
  local target_id="$3"
  local artifact_type="$4"
  shift 4
  local replacements=("$@")

  if [[ ! -e "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  if $DRY_RUN; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    info "would-copy" "$target <- $source"
    [[ ${#replacements[@]} -gt 0 ]] && info "would-sub" "$target (${#replacements[@]} replacement(s))"
    return 0
  fi

  if [[ -L "$target" || -f "$target" ]]; then
    rm -f "$target"
  elif [[ -d "$target" ]]; then
    rm -rf "$target"
  fi

  if [[ -d "$source" ]]; then
    cp -R "$source" "$target"
    prune_python_bytecode "$target"
  else
    cp "$source" "$target"
  fi

  ok "copied" "$target <- $source"
  maybe_apply_replacements "$target" "${replacements[@]}"
  SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  append_deployed_artifact_log "$target" "$target_id" "$artifact_type" "$source"
}

# ---------------------------------------------------------------------------
# Merge a top-level JSON key into a target JSON file.
# Creates the target if it doesn't exist. Logs with path[key] notation.
#
# Value source (exactly one):
#   - When scalar_value (7th arg) is provided, that string is JSON-encoded
#     as the new key value (conf-sourced scalar path). source is used only
#     for the deploy-log source column.
#   - Otherwise the value is sliced from source as .${key}. An optional
#     hooks_dir rewrites relative ./hooks/ command paths.
#
# On the first write of a key, records the previous value (compact JSON) or
# @absent when the key was missing. A later redeploy of the same key reuses
# that first-recorded prior so sort -u keeps a single line.
# ---------------------------------------------------------------------------
merge_json_key() {
  local source="$1"
  local target="$2"
  local key="$3"
  local target_id="$4"
  local artifact_type="$5"
  local hooks_dir="${6:-}"
  local scalar_value="${7-}"
  local use_scalar=false
  if [[ $# -ge 7 ]]; then
    use_scalar=true
  fi

  if ! $use_scalar && [[ ! -f "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  local log_path="${target}[${key}]"
  local log_source="$source"
  if $use_scalar && [[ -z "$log_source" ]]; then
    log_source="$DEPLOYMENT_CONF"
  fi

  if $DRY_RUN; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    if $use_scalar; then
      info "would-merge" "${target} <- .${key} = $(jq -cn --arg v "$scalar_value" '$v')"
    else
      info "would-merge" "${target} <- .${key} from ${source}"
    fi
    if [[ -n "$hooks_dir" ]]; then
      info "would-rewrite" "./hooks/ command paths -> ${hooks_dir}/"
    fi
    return 0
  fi

  local existing="{}"
  if [[ -f "$target" ]]; then
    existing="$(cat "$target")"
  fi

  # First-write prior: reuse a logged prior when present; otherwise sample.
  local prior_value=""
  if prior_value="$(lookup_logged_prior "$log_path")"; then
    :
  else
    if printf '%s' "$existing" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
      prior_value="$(printf '%s' "$existing" | jq -c --arg k "$key" '.[$k]')"
    else
      prior_value="@absent"
    fi
  fi

  local patch
  if $use_scalar; then
    patch="$(jq -cn --arg v "$scalar_value" '$v')"
  else
    patch="$(jq ".${key}" "$source")"

    # Rewrite relative ./hooks/ command paths to absolute paths
    if [[ -n "$hooks_dir" ]]; then
      patch="$(printf '%s' "$patch" | jq --arg dir "$hooks_dir" '
        walk(if type == "object" and .command and (.command | startswith("./hooks/"))
             then .command = ($dir + "/" + (.command | ltrimstr("./hooks/")))
             else . end)')"
    fi
  fi

  local merged
  merged="$(printf '%s' "$existing" | jq --argjson patch "$patch" ".${key} = \$patch")"

  printf '%s\n' "$merged" > "$target"
  ok "merged" "${target} <- .${key}"
  SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  append_deployed_artifact_log "$log_path" "$target_id" "$artifact_type" "$log_source" "$prior_value"
}

# ---------------------------------------------------------------------------
# Restore a top-level JSON key to a recorded prior value, or delete it when
# the prior is the @absent marker. Used during uninstall for newly logged
# path[key] entries that carry a fifth-field prior.
# ---------------------------------------------------------------------------
restore_json_key() {
  local target="$1"
  local key="$2"
  local prior_value="$3"

  if [[ "$prior_value" == "@absent" ]]; then
    strip_json_key "$target" "$key"
    return $?
  fi

  if [[ ! -f "$target" ]]; then
    if $DRY_RUN; then
      SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
      info "would-restore" "${target} .${key}"
      return 0
    fi
    printf '%s\n' "{}" > "$target"
  fi

  if $DRY_RUN; then
    SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
    info "would-restore" "${target} .${key}"
    return 0
  fi

  local existing
  existing="$(cat "$target")"
  local restored
  restored="$(printf '%s' "$existing" | jq --argjson patch "$prior_value" ".${key} = \$patch")"
  printf '%s\n' "$restored" > "$target"
  ok "restored" "${target} .${key}"
  SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
}

# ---------------------------------------------------------------------------
# Remove a top-level JSON key from a file. Used during uninstall for
# artifacts logged with path[key] notation.
# ---------------------------------------------------------------------------
strip_json_key() {
  local target="$1"
  local key="$2"

  if [[ ! -f "$target" ]]; then
    return 1
  fi

  if $DRY_RUN; then
    SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
    info "would-strip" "${target} .${key}"
    return 0
  fi

  local stripped
  stripped="$(jq "del(.${key})" "$target")"
  printf '%s\n' "$stripped" > "$target"
  ok "stripped" "${target} .${key}"
  SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
}

# ---------------------------------------------------------------------------
# Rewrite agent frontmatter for a specific target tool.
#
# Source .md files may contain vendor-prefixed frontmatter fields:
#   TOOLNAME_fieldname: value
# where TOOLNAME is an UPPERCASE target ID (VSCODE, CURSOR, CLAUDE, CODEX, …).
#
# For target tool X the rewriter:
#   1. Keeps non-prefixed lines unchanged (universal fields)
#   2. Strips the X_ prefix from X_fieldname lines (→ fieldname: value)
#   3. Drops lines prefixed with any other known tool ID
#
# Body content after the closing --- is passed through unchanged.
# ---------------------------------------------------------------------------
rewrite_agent_frontmatter() {
  local source="$1" dest="$2" target_id="$3" quiet="${4:-false}"

  if [[ ! -f "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  # Build uppercase target ID for matching
  local uc_target
  uc_target="$(printf '%s' "$target_id" | tr '[:lower:]' '[:upper:]')"

  # Build list of ALL known uppercase tool IDs from VALID_TARGETS
  local known_prefixes=()
  IFS=',' read -ra _vt <<< "$VALID_TARGETS"
  for _t in "${_vt[@]}"; do
    known_prefixes+=("$(printf '%s' "$_t" | tr '[:lower:]' '[:upper:]')")
  done
  unset _vt _t

  local in_frontmatter=false frontmatter_done=false
  local skip_prefixed_block=false
  local output=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! $frontmatter_done && [[ "$line" == "---" ]]; then
      output+="---"$'\n'
      if $in_frontmatter; then
        in_frontmatter=false
        frontmatter_done=true
      else
        in_frontmatter=true
      fi
      continue
    fi

    if $in_frontmatter; then
      if $skip_prefixed_block; then
        if [[ -z "$line" || "$line" == [[:space:]]* ]]; then
          continue
        fi
        skip_prefixed_block=false
      fi

      # Check if the line has a TOOLNAME_ prefix (uppercase letters followed by _)
      if [[ "$line" =~ ^([A-Z]+)_([A-Za-z0-9_-]+:.*)$ ]]; then
        local prefix="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]}"
        # If prefix matches target tool, emit without prefix
        if [[ "$prefix" == "$uc_target" ]]; then
          output+="${rest}"$'\n'
          continue
        fi
        # If prefix matches another known tool, drop the line
        local is_known=false
        for kp in "${known_prefixes[@]}"; do
          if [[ "$prefix" == "$kp" ]]; then
            is_known=true
            break
          fi
        done
        if $is_known; then
          skip_prefixed_block=true
          continue
        fi
      fi
      # Non-prefixed line or unknown prefix — keep as-is
      output+="${line}"$'\n'
      continue
    fi

    # Body — pass through unchanged
    output+="${line}"$'\n'
  done < "$source"

  if $DRY_RUN && ! $quiet; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    info "would-gen" "$dest (rewritten agent)"
    return 0
  fi

  if [[ -L "$dest" || -f "$dest" ]]; then rm "$dest"; fi

  printf '%s' "$output" > "$dest"
  if ! $quiet; then
    ok "rewritten" "$dest <- $source (target: $target_id)"
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  fi
}

escape_toml_basic_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

is_model_inherit_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi
  [[ "$value" == "inherit" ]]
}

# ---------------------------------------------------------------------------
# Generate a .toml agent for Codex CLI from a vendor-rewritten .md agent
# ---------------------------------------------------------------------------
generate_toml_agent() {
  local source="$1"
  local dest="$2"
  local target_id="$3"
  local artifact_type="$4"

  if [[ ! -f "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  # Rewrite vendor-prefixed frontmatter to a temp file first (quiet mode
  # suppresses logging and dry-run short-circuit so the file is always written)
  local tmp_rewritten
  tmp_rewritten="$(mktemp)"
  rewrite_agent_frontmatter "$source" "$tmp_rewritten" "$target_id" true

  local name="" description="" model="" model_reasoning_effort="" readonly="" body=""
  local in_frontmatter=false frontmatter_done=false in_body=false

  while IFS= read -r line; do
    if ! $frontmatter_done && [[ "$line" == "---" ]]; then
      if $in_frontmatter; then
        in_frontmatter=false
        frontmatter_done=true
      else
        in_frontmatter=true
      fi
      continue
    fi

    if $in_frontmatter; then
      if [[ "$line" =~ ^name:[[:space:]]*(.+) ]]; then
        name="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^description:[[:space:]]*(.+) ]]; then
        description="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^model:[[:space:]]*(.+) ]]; then
        model="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^model_reasoning_effort:[[:space:]]*(.+) ]]; then
        model_reasoning_effort="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^readonly:[[:space:]]*(.+) ]]; then
        readonly="${BASH_REMATCH[1]}"
      fi
      continue
    fi

    if $frontmatter_done; then
      if ! $in_body && [[ -z "$line" ]]; then continue; fi
      in_body=true
      body+="${line}"$'\n'
    fi
  done < "$tmp_rewritten"

  rm -f "$tmp_rewritten"
  body="${body%$'\n'}"

  if $DRY_RUN; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    info "would-gen" "$dest (.toml agent)"
    return 0
  fi

  if [[ -L "$dest" || -f "$dest" ]]; then rm "$dest"; fi

  {
    [[ -n "$name" ]] && printf 'name = "%s"\n' "$(escape_toml_basic_string "$name")"
    [[ -n "$description" ]] && printf 'description = "%s"\n' "$(escape_toml_basic_string "$description")"
    if [[ -n "$model" ]] && ! is_model_inherit_value "$model"; then
      printf 'model = "%s"\n' "$(escape_toml_basic_string "$model")"
    fi
    [[ -n "$model_reasoning_effort" ]] && printf 'model_reasoning_effort = "%s"\n' "$(escape_toml_basic_string "$model_reasoning_effort")"
    if [[ "$readonly" == "true" ]]; then
      printf 'sandbox_mode = "read-only"\n'
    fi
    printf 'developer_instructions = """\n%s\n"""\n' "$(escape_toml_basic_string "$body")"
  } > "$dest"

  ok "generated" "$dest (.toml agent)"
  SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  append_deployed_artifact_log "$dest" "$target_id" "$artifact_type" "$source"
}

# ---------------------------------------------------------------------------
# Generate an Antigravity agent from a vendor-rewritten .md agent.
#
# Antigravity uses markdown agents with its own frontmatter schema and native
# tool vocabulary. Emit only documented Antigravity keys so source-maintenance
# keys never become runtime options on a loader whose unknown-field tolerance is
# still unverified.
# ---------------------------------------------------------------------------
map_antigravity_tool_name() {
  case "$1" in
    Read)      printf 'view_file' ;;
    Grep)      printf 'grep_search' ;;
    Bash)      printf 'run_command' ;;
    *) return 1 ;;
  esac
}

generate_antigravity_agent() {
  local source="$1" dest="$2" target_id="$3" artifact_type="$4"

  if [[ ! -f "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  # Resolve vendor prefixes first (quiet mode always writes the temp file)
  local tmp_rewritten
  tmp_rewritten="$(mktemp)"
  rewrite_agent_frontmatter "$source" "$tmp_rewritten" "$target_id" true

  local in_frontmatter=false frontmatter_done=false in_body=false skip_block=false
  local line key value body=""
  local name="" description="" model="" readonly="" tools=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! $frontmatter_done && [[ "$line" == "---" ]]; then
      if $in_frontmatter; then
        in_frontmatter=false
        frontmatter_done=true
      else
        in_frontmatter=true
      fi
      continue
    fi

    if $in_frontmatter; then
      if $skip_block; then
        if [[ -z "$line" || "$line" == [[:space:]]* ]]; then
          continue
        fi
        skip_block=false
      fi

      if [[ "$line" =~ ^([A-Za-z0-9_-]+):[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
          name) [[ -z "$name" ]] && name="$value" ;;
          description) [[ -z "$description" ]] && description="$value" ;;
          model) [[ -z "$model" ]] && model="$value" ;;
          readonly) [[ -z "$readonly" ]] && readonly="$value" ;;
          tools) [[ -z "$tools" ]] && tools="$value" ;;
        esac
        skip_block=true
        continue
      fi

      continue
    fi

    if $frontmatter_done; then
      if ! $in_body && [[ -z "$line" ]]; then continue; fi
      in_body=true
      body+="${line}"$'\n'
    fi
  done < "$tmp_rewritten"

  rm -f "$tmp_rewritten"
  body="${body%$'\n'}"

  local mapped_tools=() raw_tools=() tool slug
  if [[ -n "$tools" ]]; then
    IFS=',' read -ra raw_tools <<< "$tools"
    for tool in "${raw_tools[@]}"; do
      tool="${tool#"${tool%%[![:space:]]*}"}"
      tool="${tool%"${tool##*[![:space:]]}"}"
      [[ -z "$tool" ]] && continue
      if slug="$(map_antigravity_tool_name "$tool")"; then
        mapped_tools+=("$slug")
      else
        warn "antigravity-agent" "dropped tool for ${dest##*/}: no Antigravity mapping for '${tool}'"
      fi
    done
  fi

  if $DRY_RUN; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    info "would-gen" "$dest (antigravity agent)"
    return 0
  fi

  if [[ -L "$dest" || -f "$dest" ]]; then rm "$dest"; fi

  {
    printf '%s\n' '---'
    [[ -n "$name" ]] && printf 'name: %s\n' "$name"
    [[ -n "$description" ]] && printf 'description: %s\n' "$description"
    if [[ ${#mapped_tools[@]} -gt 0 ]]; then
      local joined
      joined="$(printf '%s, ' "${mapped_tools[@]}")"
      printf 'tools: [%s]\n' "${joined%, }"
    fi
    if [[ -n "$model" ]] && ! is_model_inherit_value "$model"; then
      printf 'model: %s\n' "$model"
    fi
    if [[ "$readonly" == "true" && ",${tools// /}," != *",Bash,"* ]]; then
      printf '%s\n' 'commandExecutionPolicy: off'
    else
      printf '%s\n' 'commandExecutionPolicy: sandbox'
    fi
    printf '%s\n' 'mainAgent: false'
    printf '%s\n\n' '---'
    printf '%s\n' "$body"
  } > "$dest"

  ok "generated" "$dest (antigravity agent)"
  SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  append_deployed_artifact_log "$dest" "$target_id" "$artifact_type" "$source"
}

# ---------------------------------------------------------------------------
# Generate an OpenCode agent from a vendor-rewritten .md agent
#
# OpenCode passes unrecognized frontmatter options through to the provider as
# model options (opencode.ai/docs/agents, verified July 2026), so this bridge
# emits only OpenCode schema keys and drops repo-maintenance fields such as
# version, background, effort, model_reasoning_effort, and name.
# ---------------------------------------------------------------------------
generate_opencode_agent() {
  local source="$1" dest="$2" target_id="$3" artifact_type="$4"

  if [[ ! -f "$source" ]]; then
    err "missing" "source not found: $source"
    return 1
  fi

  # Resolve vendor prefixes first (quiet mode always writes the temp file).
  local tmp_rewritten
  tmp_rewritten="$(mktemp)"
  rewrite_agent_frontmatter "$source" "$tmp_rewritten" "$target_id" true

  local in_frontmatter=false frontmatter_done=false in_body=false
  local skip_block=false body="" line key value
  local description="" model="" temperature="" readonly="" tools=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! $frontmatter_done && [[ "$line" == "---" ]]; then
      if $in_frontmatter; then
        in_frontmatter=false
        frontmatter_done=true
      else
        in_frontmatter=true
      fi
      continue
    fi

    if $in_frontmatter; then
      if $skip_block; then
        if [[ -z "$line" || "$line" == [[:space:]]* ]]; then
          continue
        fi
        skip_block=false
      fi

      if [[ "$line" =~ ^([A-Za-z0-9_-]+):[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$key" in
          description) [[ -z "$description" ]] && description="$value" ;;
          model) [[ -z "$model" ]] && model="$value" ;;
          temperature) [[ -z "$temperature" ]] && temperature="$value" ;;
          readonly) [[ -z "$readonly" ]] && readonly="$value" ;;
          tools) [[ -z "$tools" ]] && tools="$value" ;;
        esac
        skip_block=true
      fi
      continue
    fi

    if $frontmatter_done; then
      if ! $in_body && [[ -z "$line" ]]; then continue; fi
      in_body=true
      body+="${line}"$'\n'
    fi
  done < "$tmp_rewritten"

  rm -f "$tmp_rewritten"
  body="${body%$'\n'}"

  if $DRY_RUN; then
    SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
    info "would-gen" "$dest (opencode agent)"
    return 0
  fi

  if [[ -L "$dest" || -f "$dest" ]]; then rm "$dest"; fi

  {
    printf '%s\n' '---'
    printf '%s\n' 'mode: subagent'
    [[ -n "$description" ]] && printf 'description: %s\n' "$description"
    if [[ -n "$model" ]] && ! is_model_inherit_value "$model"; then
      printf 'model: %s\n' "$model"
    fi
    [[ -n "$temperature" ]] && printf 'temperature: %s\n' "$temperature"
    if [[ "$readonly" == "true" ]]; then
      if [[ ",${tools// /}," == *",Bash,"* ]]; then
        printf '%s\n' 'permission: { edit: deny }'
      else
        printf '%s\n' 'permission: { edit: deny, bash: deny }'
      fi
    fi
    printf '%s\n\n' '---'
    printf '%s\n' "$body"
  } > "$dest"

  ok "generated" "$dest (opencode agent)"
  SUMMARY_DEPLOY_ACTIONS=$((SUMMARY_DEPLOY_ACTIONS + 1))
  append_deployed_artifact_log "$dest" "$target_id" "$artifact_type" "$source"
}

# ---------------------------------------------------------------------------
# Install a single artifact into one app target
# ---------------------------------------------------------------------------
install_for_app() {
  local app_id="$1" app_dir="$2" name="$3" type="$4" source_abs="$5" rel_path="$6"
  local replacement_specs=()
  local spec=""

  while IFS= read -r spec; do
    [[ -n "$spec" ]] && replacement_specs+=("$spec")
  done < <(get_matching_replacements "$app_id" "$rel_path")

  case "$type" in
    command)
      case "$app_id" in
        vscode)
          ensure_dir "$VSCODE_PROMPTS_DIR"
          local dest_path="${VSCODE_PROMPTS_DIR}/${name}.prompt.md"
          copy_path_with_replacements "$source_abs" "$dest_path" "$app_id" "$type" "${replacement_specs[@]}"
          ;;
        antigravity)
          info "skip" "[$name] Antigravity command workflow deployment is not supported"
          ;;
        codex)
          local dest_dir="${app_dir}/prompts"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.md"
          copy_path_with_replacements "$source_abs" "$dest_path" "$app_id" "$type" "${replacement_specs[@]}"
          ;;
        *)
          local dest_dir="${app_dir}/commands"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.md"
          copy_path_with_replacements "$source_abs" "$dest_path" "$app_id" "$type" "${replacement_specs[@]}"
          ;;
      esac
      ;;
    skill)
      # Codex project-level skills go to .agents/skills/ not .codex/skills/
      local dest_dirs=()
      local log_owner="$app_id"
      if [[ "$app_id" == "codex" && -n "$CODEX_SKILLS_DIR" ]]; then
        dest_dirs=("$CODEX_SKILLS_DIR")
      elif [[ "$app_id" == "antigravity" && -n "$PROJECT_DIR" ]]; then
        if target_is_active "codex"; then
          info "skip" "[$name] shared .agents/skills tree owned by codex in project-dir mode"
          return 0
        fi
        dest_dirs=("${ANTIGRAVITY_DIR}/skills")
        log_owner="codex"
      elif [[ "$app_id" == "antigravity" ]]; then
        dest_dirs=(
          "${ANTIGRAVITY_TREE_DIR}/config/skills"
          "${ANTIGRAVITY_TREE_DIR}/antigravity/skills"
          "${ANTIGRAVITY_TREE_DIR}/antigravity-cli/skills"
        )
      else
        dest_dirs=("${app_dir}/skills")
      fi
      local dest_dir
      for dest_dir in "${dest_dirs[@]}"; do
        ensure_dir "$dest_dir"
        local dest_path="${dest_dir}/${name}"
        copy_path_with_replacements "$source_abs" "$dest_path" "$log_owner" "$type" "${replacement_specs[@]}"
      done
      ;;
    agent)
      case "$app_id" in
        vscode)
          local dest_dir="${app_dir}/agents"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.agent.md"
          rewrite_agent_frontmatter "$source_abs" "$dest_path" "$app_id"
          $DRY_RUN || append_deployed_artifact_log "$dest_path" "$app_id" "$type" "$source_abs"
          maybe_apply_replacements "$dest_path" "${replacement_specs[@]}"
          ;;
        cursor|claude)
          local dest_dir="${app_dir}/agents"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.md"
          rewrite_agent_frontmatter "$source_abs" "$dest_path" "$app_id"
          $DRY_RUN || append_deployed_artifact_log "$dest_path" "$app_id" "$type" "$source_abs"
          maybe_apply_replacements "$dest_path" "${replacement_specs[@]}"
          ;;
        codex)
          local dest_dir="${app_dir}/agents"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.toml"
          generate_toml_agent "$source_abs" "$dest_path" "$app_id" "$type"
          maybe_apply_replacements "$dest_path" "${replacement_specs[@]}"
          ;;
        opencode)
          local dest_dir="${app_dir}/agents"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.md"
          generate_opencode_agent "$source_abs" "$dest_path" "$app_id" "$type"
          maybe_apply_replacements "$dest_path" "${replacement_specs[@]}"
          ;;
        antigravity)
          local dest_dir="${app_dir}/agents"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.md"
          generate_antigravity_agent "$source_abs" "$dest_path" "$app_id" "$type"
          maybe_apply_replacements "$dest_path" "${replacement_specs[@]}"
          ;;
      esac
      ;;
    hook)
      local src_ext="${source_abs##*.}"
      case "$src_ext" in
        sh|json) ;;
        *)
          info "skip" "[$name] not an executable hook or hook config"
          return 0
          ;;
      esac
      case "$app_id" in
        vscode)
          local dest_dir="${app_dir}/hooks"
          ensure_dir "$dest_dir"
          local dest_file
          dest_file="${dest_dir}/$(basename "$source_abs")"
          if [[ ${#replacement_specs[@]} -gt 0 ]]; then
            copy_path_with_replacements "$source_abs" "$dest_file" "$app_id" "$type" "${replacement_specs[@]}"
          else
            copy_file "$source_abs" "$dest_file" "$app_id" "$type"
          fi
          if [[ "$src_ext" == "sh" && ! $DRY_RUN ]]; then chmod +x "$dest_file"; fi
          ;;
        cursor)
          if [[ "$src_ext" == "json" ]]; then
            # Only deploy the Cursor-specific config; skip other JSON configs
            [[ "$source_abs" == *cursor-hooks* ]] || { info "skip" "[$name] not a Cursor hook config"; return 0; }
            local dest_path="${app_dir}/hooks.json"
            if [[ ${#replacement_specs[@]} -gt 0 ]]; then
              copy_path_with_replacements "$source_abs" "$dest_path" "$app_id" "$type" "${replacement_specs[@]}"
            else
              copy_file "$source_abs" "$dest_path" "$app_id" "$type"
            fi
          elif [[ "$src_ext" == "sh" ]]; then
            local dest_dir="${app_dir}/hooks"
            ensure_dir "$dest_dir"
            local dest_file
            dest_file="${dest_dir}/$(basename "$source_abs")"
            if [[ ${#replacement_specs[@]} -gt 0 ]]; then
              copy_path_with_replacements "$source_abs" "$dest_file" "$app_id" "$type" "${replacement_specs[@]}"
            else
              copy_file "$source_abs" "$dest_file" "$app_id" "$type"
            fi
            if ! $DRY_RUN; then chmod +x "$dest_file"; fi
          fi
          ;;
        claude)
          if [[ "$src_ext" == "json" ]]; then
            # Only deploy the Claude Code-specific config; skip other JSON configs
            [[ "$source_abs" == *claude-code-hooks* ]] || { info "skip" "[$name] not a Claude hook config"; return 0; }
            # Merge the hooks key into settings.json. Global deployment uses absolute
            # script paths; project-dir uses paths relative to the project root so
            # the repo stays portable across machines.
            local hooks_dir
            if [[ -n "$PROJECT_DIR" ]]; then
              hooks_dir=".claude/hooks"
            else
              hooks_dir="${app_dir}/hooks"
            fi
            merge_json_key "$source_abs" "${app_dir}/settings.json" "hooks" "$app_id" "$type" "$hooks_dir"
          elif [[ "$src_ext" == "sh" ]]; then
            local dest_dir="${app_dir}/hooks"
            ensure_dir "$dest_dir"
            local dest_file
            dest_file="${dest_dir}/$(basename "$source_abs")"
            if [[ ${#replacement_specs[@]} -gt 0 ]]; then
              copy_path_with_replacements "$source_abs" "$dest_file" "$app_id" "$type" "${replacement_specs[@]}"
            else
              copy_file "$source_abs" "$dest_file" "$app_id" "$type"
            fi
            if ! $DRY_RUN; then chmod +x "$dest_file"; fi
          fi
          ;;
        codex)
          if [[ "$src_ext" == "json" ]]; then
            # Only deploy the Codex config-layer hook config; skip Claude/plugin configs.
            local source_file
            source_file="$(basename "$source_abs")"
            if [[ "$source_file" != "codex-custom-deploy-hooks.json" ]]; then
              info "skip" "[$name] not a Codex custom deploy hook config"
              return 0
            fi
            local hooks_dir="${app_dir}/hooks"
            merge_json_key "$source_abs" "${app_dir}/hooks.json" "hooks" "$app_id" "$type" "$hooks_dir"
          elif [[ "$src_ext" == "sh" ]]; then
            local dest_dir="${app_dir}/hooks"
            ensure_dir "$dest_dir"
            local dest_file
            dest_file="${dest_dir}/$(basename "$source_abs")"
            if [[ ${#replacement_specs[@]} -gt 0 ]]; then
              copy_path_with_replacements "$source_abs" "$dest_file" "$app_id" "$type" "${replacement_specs[@]}"
            else
              copy_file "$source_abs" "$dest_file" "$app_id" "$type"
            fi
            if ! $DRY_RUN; then chmod +x "$dest_file"; fi
          fi
          ;;
        antigravity)
          if [[ "$src_ext" == "json" ]]; then
            local source_file
            source_file="$(basename "$source_abs")"
            if [[ "$source_file" != "antigravity-hooks.json" ]]; then
              info "skip" "[$name] not an Antigravity hook config"
              return 0
            fi
            local hooks_dir
            if [[ -n "$PROJECT_DIR" ]]; then
              hooks_dir=".agents/hooks"
            else
              hooks_dir="${app_dir}/hooks"
            fi
            merge_json_key "$source_abs" "${app_dir}/hooks.json" "charter_guardrail" "$app_id" "$type" "$hooks_dir"
          elif [[ "$src_ext" == "sh" ]]; then
            local dest_dir="${app_dir}/hooks"
            ensure_dir "$dest_dir"
            local dest_file
            dest_file="${dest_dir}/$(basename "$source_abs")"
            if [[ ${#replacement_specs[@]} -gt 0 ]]; then
              copy_path_with_replacements "$source_abs" "$dest_file" "$app_id" "$type" "${replacement_specs[@]}"
            else
              copy_file "$source_abs" "$dest_file" "$app_id" "$type"
            fi
            if ! $DRY_RUN; then chmod +x "$dest_file"; fi
          fi
          ;;
        *)
          info "skip" "[$name] Hook deployment not implemented for $app_id"
          ;;
      esac
      ;;
    style)
      case "$app_id" in
        claude)
          local dest_dir="${app_dir}/output-styles"
          ensure_dir "$dest_dir"
          local dest_path="${dest_dir}/${name}.md"
          if [[ ${#replacement_specs[@]} -gt 0 ]]; then
            copy_path_with_replacements "$source_abs" "$dest_path" "$app_id" "$type" "${replacement_specs[@]}"
          else
            copy_file "$source_abs" "$dest_path" "$app_id" "$type"
          fi

          local active_style="${STYLE_MAP[$app_id]:-}"
          if [[ -z "$active_style" ]]; then
            warn "skip" "[$name] no style:<name> in deployment.conf for $app_id; file copied, outputStyle not set"
          elif [[ "$active_style" != "$name" ]]; then
            info "skip" "[$name] active style for $app_id is '${active_style}'; file copied only"
          else
            # Conf-sourced scalar: empty hooks_dir, scalar as 7th arg.
            # source for the log column is deployment.conf (no JSON file read).
            merge_json_key "$DEPLOYMENT_CONF" "${app_dir}/settings.json" "outputStyle" "$app_id" "$type" "" "$active_style"
          fi
          ;;
        *)
          info "skip" "[$name] style deployment not implemented for $app_id"
          ;;
      esac
      ;;
    *)
      err "unknown" "artifact type: $type"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Backup — only activated targets
# ---------------------------------------------------------------------------
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

is_managed_backup_path() {
  local app_dir="$1"
  local candidate="$2"
  local backup_name_override="${3:-}"

  [[ "$candidate" = /* ]] || return 1
  [[ "$(dirname "$candidate")" == "$HOME_DIR" ]] || return 1
  [[ "$candidate" != "$app_dir" ]] || return 1

  local app_name backup_name suffix
  if [[ -n "$backup_name_override" ]]; then
    app_name="$backup_name_override"
  else
    app_name="$(basename "$app_dir")"
  fi
  backup_name="$(basename "$candidate")"

  [[ "$backup_name" == "${app_name}_"* ]] || return 1
  suffix="${backup_name#"${app_name}"_}"
  [[ "$suffix" =~ ^[0-9]{8}_[0-9]{6}$ ]]
}

clear_old_backups_for_app_dir() {
  local app_dir="$1"
  local backup_name_override="${2:-}"
  local app_name
  if [[ -n "$backup_name_override" ]]; then
    app_name="$backup_name_override"
  else
    app_name="$(basename "$app_dir")"
  fi

  local _old_nullglob
  _old_nullglob="$(shopt -p nullglob)" || true
  shopt -s nullglob

  local candidate
  for candidate in "${HOME_DIR}/${app_name}_"*; do
    if ! is_managed_backup_path "$app_dir" "$candidate" "$backup_name_override"; then
      continue
    fi

    if $DRY_RUN; then
      SUMMARY_CLEARED_BACKUPS=$((SUMMARY_CLEARED_BACKUPS + 1))
      info "would-clr" "$candidate"
      continue
    fi

    if [[ -L "$candidate" || -f "$candidate" ]]; then
      rm -f "$candidate"
    elif [[ -d "$candidate" ]]; then
      rm -rf "$candidate"
    else
      continue
    fi

    ok "cleared" "$candidate"
    SUMMARY_CLEARED_BACKUPS=$((SUMMARY_CLEARED_BACKUPS + 1))
  done

  eval "$_old_nullglob"
}

clear_backups_for_active_targets() {
  declare -A cleared_roots=()
  for target in "${APP_TARGETS[@]}"; do
    IFS='|' read -r app_id _label base_dir <<< "$target"
    # Each backup_roots entry is "path|backup_name". An empty backup_name
    # falls back to basename(path). Override the name only when the basename
    # isn't tool-distinctive — see the header comment for context.
    local backup_roots=("$base_dir|")
    if [[ "$app_id" == "antigravity" ]]; then
      backup_roots=("${ANTIGRAVITY_TREE_DIR}|")
    elif [[ "$app_id" == "opencode" ]]; then
      backup_roots=("${OPENCODE_DIR}|.opencode-config")
    elif [[ "$app_id" == "vscode" ]]; then
      backup_roots=("${VSCODE_COPILOT_DIR}|" "${VSCODE_PROMPTS_DIR}|.vscode-prompts")
    fi

    local backup_root_entry local_backup_root local_backup_name
    for backup_root_entry in "${backup_roots[@]}"; do
      local_backup_root="${backup_root_entry%%|*}"
      local_backup_name="${backup_root_entry#*|}"
      if [[ -z "${cleared_roots[$local_backup_root]+x}" ]]; then
        clear_old_backups_for_app_dir "$local_backup_root" "$local_backup_name"
        cleared_roots["$local_backup_root"]=1
      fi
    done
  done
}

backup_app_dir() {
  local app_dir="$1"
  local backup_name_override="${2:-}"
  local app_name
  if [[ -n "$backup_name_override" ]]; then
    app_name="$backup_name_override"
  else
    app_name="$(basename "$app_dir")"
  fi
  local backup_dir="${HOME_DIR}/${app_name}_${TIMESTAMP}"

  if [[ ! -d "$app_dir" ]]; then
    info "no backup" "$app_dir does not exist yet"
    return 0
  fi

  if $DRY_RUN; then
    SUMMARY_BACKUPS=$((SUMMARY_BACKUPS + 1))
    info "would-bak" "$app_dir -> $backup_dir"
    return 0
  fi

  cp -a "$app_dir" "$backup_dir"
  ok "backup" "$backup_dir"
  SUMMARY_BACKUPS=$((SUMMARY_BACKUPS + 1))
}

logged_type_matches_filter() {
  local artifact_type="$1"
  matches_filter "$artifact_type" "$TYPE_FILTER"
}

remove_logged_path() {
  local path="$1"
  local prior_value="${2:-}"

  # Handle path[key] notation — restore recorded prior or strip the key
  if [[ "$path" =~ ^(.+)\[([a-zA-Z_][a-zA-Z0-9_]*)\]$ ]]; then
    local json_file="${BASH_REMATCH[1]}"
    local json_key="${BASH_REMATCH[2]}"
    if [[ -n "$prior_value" ]]; then
      restore_json_key "$json_file" "$json_key" "$prior_value"
      return $?
    fi
    strip_json_key "$json_file" "$json_key"
    return $?
  fi

  if [[ "$path" == "$REPO_ROOT/"* ]]; then
    local repo_rel="${path#"$REPO_ROOT"/}"
    if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$repo_rel" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" rm -r --force -- "$repo_rel" >/dev/null 2>&1
      return $?
    fi
  fi

  if [[ -L "$path" || -f "$path" ]]; then
    rm -f "$path"
  elif [[ -d "$path" ]]; then
    rm -rf "$path"
  else
    return 1
  fi
}

# Success check after uninstalling a logged path.
# For path[key] with a recorded prior value, the key may still be present
# after restore; absence is success only for @absent or legacy four-field strips.
json_key_uninstall_succeeded() {
  local path="$1"
  local prior_value="${2:-}"

  if [[ "$path" =~ ^(.+)\[([a-zA-Z_][a-zA-Z0-9_]*)\]$ ]]; then
    local json_file="${BASH_REMATCH[1]}"
    local json_key="${BASH_REMATCH[2]}"

    if [[ -n "$prior_value" && "$prior_value" != "@absent" ]]; then
      [[ -f "$json_file" ]] || return 1
      local current
      current="$(jq -c --arg k "$json_key" '.[$k]' "$json_file" 2>/dev/null)" || return 1
      [[ "$current" == "$prior_value" ]]
      return $?
    fi

    # @absent or legacy four-field: key must be gone
    if [[ -f "$json_file" ]] && jq -e --arg k "$json_key" 'has($k)' "$json_file" >/dev/null 2>&1; then
      return 1
    fi
    return 0
  fi

  ! path_exists "$path"
}

uninstall_logged_artifacts() {
  echo "Uninstalling logged artifacts..."
  echo ""

  if [[ ! -f "$DEPLOYED_ARTIFACTS_LOG" ]]; then
    info "skip" "No deploy log found at $DEPLOYED_ARTIFACTS_LOG"
    return 0
  fi

  local remaining_entries=()
  local removed_count=0
  local logged_entry=""

  while IFS= read -r logged_entry || [[ -n "$logged_entry" ]]; do
    [[ -n "$logged_entry" ]] || continue

    local logged_path="" logged_target_id="" logged_type="" logged_source="" logged_prior=""
    IFS=$'\t' read -r logged_path logged_target_id logged_type logged_source logged_prior <<< "$logged_entry"

    if [[ -z "$logged_path" || -z "$logged_target_id" || -z "$logged_type" || -z "$logged_source" ]]; then
      warn "skip" "Malformed log entry: $logged_entry"
      remaining_entries+=("$logged_entry")
      continue
    fi

    if ! logged_path_matches_active_targets "$logged_target_id"; then
      if [[ -z "$TARGET_FILTER" ]]; then
        info "stale" "$logged_path targets removed app '$logged_target_id'"
      else
        remaining_entries+=("$logged_entry")
        continue
      fi
    fi

    if ! logged_type_matches_filter "$logged_type"; then
      remaining_entries+=("$logged_entry")
      continue
    fi

    if $DRY_RUN; then
      SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
      if [[ "$logged_path" =~ ^(.+)\[([a-zA-Z_][a-zA-Z0-9_]*)\]$ ]]; then
        if [[ -n "$logged_prior" && "$logged_prior" != "@absent" ]]; then
          info "would-restore" "$logged_path"
        else
          info "would-strip" "$logged_path"
        fi
      else
        info "would-rm" "$logged_path"
      fi
      remaining_entries+=("$logged_entry")
      continue
    fi

    # path[key] with a restore prior: key absence is not "already cleaned"
    # when we still need to write the prior back.
    local skip_absent_shortcircuit=false
    if [[ "$logged_path" =~ \[.*\]$ && -n "$logged_prior" && "$logged_prior" != "@absent" ]]; then
      skip_absent_shortcircuit=true
    fi

    if ! $skip_absent_shortcircuit && ! path_exists "$logged_path"; then
      ok "cleaned" "$logged_path already absent"
      SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
      removed_count=$((removed_count + 1))
      continue
    fi

    if ! remove_logged_path "$logged_path" "$logged_prior"; then
      err "failed" "Could not remove $logged_path"
      remaining_entries+=("$logged_entry")
      continue
    fi

    if ! json_key_uninstall_succeeded "$logged_path" "$logged_prior"; then
      err "failed" "$logged_path still exists after removal"
      remaining_entries+=("$logged_entry")
      continue
    fi

    ok "removed" "$logged_path"
    SUMMARY_UNINSTALL_ACTIONS=$((SUMMARY_UNINSTALL_ACTIONS + 1))
    removed_count=$((removed_count + 1))
  done < "$DEPLOYED_ARTIFACTS_LOG"

  if $DRY_RUN; then
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  if [[ ${#remaining_entries[@]} -gt 0 ]]; then
    printf '%s\n' "${remaining_entries[@]}" > "$tmp"
  fi
  mv "$tmp" "$DEPLOYED_ARTIFACTS_LOG"
  info "log" "Removed ${removed_count} item(s); kept ${#remaining_entries[@]} item(s)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# Tests may source this file as a library after setting argv, then stop here.
if [[ "${DEPLOYMENT_SH_SKIP_MAIN:-}" == "1" ]]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
  fi
  exit 0
fi

echo ""
echo "Repo root:     $REPO_ROOT"
if [[ -n "$PROJECT_DIR" ]]; then
  echo "Project dir:   $PROJECT_DIR"
elif [[ "$GLOBAL_MODE" == true ]]; then
  echo "Global mode:   enabled"
else
  echo "Home:          $HOME_DIR"
fi
$DRY_RUN && echo "Mode:          DRY RUN (simulated only, no changes written)"
$UNINSTALL && echo "Uninstall:     enabled"
$CLEAR_BACKUPS && echo "Clear backups: enabled"
[[ -n "$TYPE_FILTER" ]] && echo "Types:         $TYPE_FILTER"
[[ -n "$TARGET_FILTER" ]] && echo "Targets:       $TARGET_FILTER"
[[ -f "$DEPLOYMENT_CONF" ]] && echo "Config:        $DEPLOYMENT_CONF"
echo ""

# Parse deployment.conf
parse_deployment_conf

# ---------------------------------------------------------------------------
# Backup activated targets only (disabled in project-dir mode)
# ---------------------------------------------------------------------------
if [[ -n "$PROJECT_DIR" ]]; then
  info "skip" "Backups are disabled in project-dir mode"
  echo ""
elif $BACKUP_CLEANUP_ONLY; then
  echo "Clearing managed backups for activated target directories..."
  echo ""
  clear_backups_for_active_targets
  echo ""
  print_summary
  echo ""
  echo "Done."
  exit 0
else
  echo "Backing up activated target directories..."
  echo ""

  declare -A backed_up=()
  for target in "${APP_TARGETS[@]}"; do
    IFS='|' read -r app_id _label base_dir <<< "$target"
    # Each backup_roots entry is "path|backup_name". An empty backup_name
    # falls back to basename(path). Override the name only when the basename
    # isn't tool-distinctive — see the header comment for context.
    backup_roots=("$base_dir|")
    if [[ "$app_id" == "antigravity" ]]; then
      backup_roots=("${ANTIGRAVITY_TREE_DIR}|")
    elif [[ "$app_id" == "opencode" ]]; then
      backup_roots=("${OPENCODE_DIR}|.opencode-config")
    elif [[ "$app_id" == "vscode" ]]; then
      backup_roots=("${VSCODE_COPILOT_DIR}|" "${VSCODE_PROMPTS_DIR}|.vscode-prompts")
    fi

    for backup_root_entry in "${backup_roots[@]}"; do
      local_backup_root="${backup_root_entry%%|*}"
      local_backup_name="${backup_root_entry#*|}"
      if [[ -z "${backed_up[$local_backup_root]+x}" ]]; then
        if $CLEAR_BACKUPS; then
          clear_old_backups_for_app_dir "$local_backup_root" "$local_backup_name"
        fi
        if [[ "$NO_SCOPE_UNINSTALL" == true && "$CLEAR_BACKUPS" == true ]]; then
          info "skip" "Fresh backup disabled for no-scope --clear-backups --uninstall"
        else
          backup_app_dir "$local_backup_root" "$local_backup_name"
        fi
        backed_up["$local_backup_root"]=1
      fi
    done
  done

  echo ""
fi

if $UNINSTALL; then
  uninstall_logged_artifacts
  echo ""
  print_summary
  echo ""
  echo "Done."
  exit 0
fi

# ---------------------------------------------------------------------------
# Discover artifacts
# ---------------------------------------------------------------------------
echo "Discovering artifacts..."
echo ""

ARTIFACTS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ARTIFACTS+=("$line")
done < <(discover_artifacts)

if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
  warn "empty" "No artifacts found matching the given filters"
  echo ""
  echo "Done (nothing to deploy)."
  exit 0
fi

echo "  Found ${#ARTIFACTS[@]} artifact(s):"
for entry in "${ARTIFACTS[@]}"; do
  IFS='|' read -r name type _rel <<< "$entry"
  printf "    \033[36m%-30s\033[0m %s\n" "$name" "$type"
done
echo ""

# ---------------------------------------------------------------------------
# Ensure base directories exist for activated targets
# ---------------------------------------------------------------------------
for target in "${APP_TARGETS[@]}"; do
  IFS='|' read -r _id _label base_dir <<< "$target"
  ensure_dir "$base_dir"
done

echo ""
echo "Installing artifacts..."
echo ""

for entry in "${ARTIFACTS[@]}"; do
  IFS='|' read -r name type rel_path <<< "$entry"
  source_abs="${REPO_ROOT}/${rel_path}"
  printf "  \033[1m%s\033[0m (%s)\n" "$name" "$type"

  for target in "${APP_TARGETS[@]}"; do
    IFS='|' read -r app_id _ base_dir <<< "$target"

    # Check deployment.conf disallow rules
    if is_disallowed "$app_id" "$rel_path"; then
      info "disallow" "[$name] excluded for $app_id (deployment.conf)"
      continue
    fi

    install_for_app "$app_id" "$base_dir" "$name" "$type" "$source_abs" "$rel_path"
  done

  echo ""
done

echo ""
print_summary
echo ""
echo "Done."
