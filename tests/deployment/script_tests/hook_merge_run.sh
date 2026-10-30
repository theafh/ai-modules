#!/usr/bin/env bash
# Regression coverage for the entry-grain hook merge.
#
# A deploy writes ai-modules' hook entries into each harness's shared hook
# file entry by entry: a missing entry is added, an existing one is updated in
# place, an owned entry the shipped config no longer carries is removed, and
# every entry the user or another tool put there stays where it was. Uninstall
# removes only the entries ai-modules added.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
# Invoke the deploy script on the stock bash the floor targets.
DEPLOY_BASH="/bin/bash"
FIXTURES="${SCRIPT_DIR}/fixtures"
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

# Checksum one file, so the dry-run snapshot compares content and not just
# names. A machine that carries neither tool must fail loudly: an empty digest
# would make the comparison pass without testing anything.
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'FAIL: neither shasum nor sha256sum is available to checksum %s\n' "$1" >&2
    exit 1
  fi
}

# Recursive listing plus per-file checksums, relative to the tree root.
snapshot_tree() {
  local root="$1" rel=""
  (
    cd "$root" || exit 1
    find . -mindepth 1 -type f | LC_ALL=C sort | while IFS= read -r rel; do
      printf '%s  %s\n' "$(sha256_of "$rel")" "$rel"
    done
  )
}

cd "$REPO_ROOT"

assert_file "$DEPLOY_SCRIPT"

# ---------------------------------------------------------------------------
# A sandbox home and project. The log override keeps the repo's own deploy log
# out of every scenario, so the harness leaves no trace in the checkout.
# ---------------------------------------------------------------------------
GLOBAL_HOME="${SCRATCH}/global-home"
GLOBAL_LOG="${SCRATCH}/global-deploy.log"
PROJECT_DIR="${SCRATCH}/project"
PROJECT_LOG="${SCRATCH}/project-deploy.log"

mkdir -p "$GLOBAL_HOME/.codex" "$PROJECT_DIR/.codex"

deploy_global_codex() {
  HOME="$GLOBAL_HOME" DEPLOYED_ARTIFACTS_LOG="$GLOBAL_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex "$@"
}

deploy_project_codex() {
  HOME="$GLOBAL_HOME" DEPLOYED_ARTIFACTS_LOG="$PROJECT_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" \
    --type hook --target codex
}

codex_hooks="${GLOBAL_HOME}/.codex/hooks.json"

# ---------------------------------------------------------------------------
# Item 1: foreign groups survive a global Codex hook deploy in place, and
# ai-modules' guard group lands exactly once.
# ---------------------------------------------------------------------------
printf '%s\n' '{"hooks":{
  "PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}],
  "PostToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-post"}]}]
}}' > "$codex_hooks"
foreign_pre="$(jq -c '.hooks.PreToolUse[0]' "$codex_hooks")"
foreign_post="$(jq -c '.hooks.PostToolUse[0]' "$codex_hooks")"

deploy_global_codex >/dev/null

assert_eq "$(jq -c '.hooks.PreToolUse[0]' "$codex_hooks")" "$foreign_pre" \
  "deploy must keep the foreign PreToolUse group at position 0"
assert_eq "$(jq -c '.hooks.PostToolUse[0]' "$codex_hooks")" "$foreign_post" \
  "deploy must keep the foreign PostToolUse group at position 0"
guard_count="$(jq '[.hooks.PreToolUse[] | select([.hooks[]?.command] | map(select(endswith("charter_guardrail.sh"))) | length > 0)] | length' "$codex_hooks")"
assert_eq "$guard_count" "1" "deploy must hold ai-modules' guard group exactly once"
assert_eq "$(jq '.hooks.PreToolUse | length' "$codex_hooks")" "2" \
  "PreToolUse must hold the foreign group plus one owned group"

# ---------------------------------------------------------------------------
# Item 2: a second identical deploy leaves the file byte-identical.
# ---------------------------------------------------------------------------
first_result="${SCRATCH}/codex-hooks-after-first.json"
cp "$codex_hooks" "$first_result"
deploy_global_codex >/dev/null
cmp -s "$first_result" "$codex_hooks" ||
  fail "a second identical deploy must leave hooks.json byte-identical"

# ---------------------------------------------------------------------------
# Item 9: a dry run lists each add/update/remove under would-merge naming the
# target, keeps the would-rewrite line, and writes nothing.
# ---------------------------------------------------------------------------
snapshot_before="$(snapshot_tree "$GLOBAL_HOME")"
dry_out="$(deploy_global_codex --dry-run)"
printf '%s\n' "$dry_out" | grep -q 'would-merge.*\.codex/hooks\.json' ||
  fail "dry run must report would-merge naming .codex/hooks.json, got: $dry_out"
printf '%s\n' "$dry_out" | grep -q 'would-rewrite.*\.codex/hooks/' ||
  fail "dry run must keep the would-rewrite line naming the Codex hooks dir, got: $dry_out"
# A second identical deploy would update the owned entry in place.
printf '%s\n' "$dry_out" | grep -q 'would-merge.*update PreToolUse' ||
  fail "dry run must report the entry it would update, got: $dry_out"
snapshot_after="$(snapshot_tree "$GLOBAL_HOME")"
assert_eq "$snapshot_after" "$snapshot_before" \
  "dry run must leave the sandbox files byte-identical"

# A dry run over a file that lacks ai-modules' entry reports an add.
rm -f "$codex_hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' > "$codex_hooks"
add_dry="$(deploy_global_codex --dry-run)"
printf '%s\n' "$add_dry" | grep -q 'would-merge.*add PreToolUse' ||
  fail "dry run must report the entry it would add, got: $add_dry"

# A dry run whose manifest lists a retired entry reports a remove.
printf '%s\t%s\t%s\t%s\t%s\n' \
  "${codex_hooks}[hooks]" codex hook plugins/ai_dev/hooks/codex-custom-deploy-hooks.json \
  '@entries:[{"event":"PreToolUse","identity":"/opt/retired/guard.sh"}]' > "$GLOBAL_LOG"
printf '%s\n' '{"hooks":{"PreToolUse":[
  {"matcher":"Retired","hooks":[{"type":"command","command":"/opt/retired/guard.sh"}]}
]}}' > "$codex_hooks"
remove_dry="$(deploy_global_codex --dry-run)"
printf '%s\n' "$remove_dry" | grep -q 'would-merge.*remove PreToolUse' ||
  fail "dry run must report the entry it would remove, got: $remove_dry"

# ---------------------------------------------------------------------------
# Item 3: a project-dir Codex deploy keeps a foreign group and adds the guard.
# ---------------------------------------------------------------------------
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/project-foreign"}]}]}}' \
  > "${PROJECT_DIR}/.codex/hooks.json"
deploy_project_codex >/dev/null
assert_eq "$(jq -r '.hooks.PreToolUse[0].matcher' "${PROJECT_DIR}/.codex/hooks.json")" "Foreign" \
  "project deploy must keep the foreign group at position 0"
assert_eq "$(jq '.hooks.PreToolUse | length' "${PROJECT_DIR}/.codex/hooks.json")" "2" \
  "project deploy must add exactly one owned group"
assert_eq "$(jq '[.hooks.PreToolUse[] | select([.hooks[]?.command] | map(select(endswith("charter_guardrail.sh"))) | length > 0)] | length' "${PROJECT_DIR}/.codex/hooks.json")" "1" \
  "project deploy must hold ai-modules' group exactly once"

# ---------------------------------------------------------------------------
# Item 4: a fixture config with a changed matcher updates ai-modules' group at
# the position it already holds and leaves the foreign groups unchanged.
# ---------------------------------------------------------------------------
UPDATE_HOME="${SCRATCH}/update-home"
UPDATE_LOG="${SCRATCH}/update-deploy.log"
mkdir -p "$UPDATE_HOME"
update_target="${UPDATE_HOME}/hooks.json"
printf '%s\n' '{"hooks":{
  "PreToolUse":[
    {"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},
    {"matcher":"^(apply_patch|Bash)$","hooks":[{"type":"command","command":"/opt/old/hooks/charter_guardrail.sh"}]},
    {"matcher":"Foreign2","hooks":[{"type":"command","command":"/bin/foreign-two"}]}
  ]
}}' > "$update_target"
foreign_pre="$(jq -c '.hooks.PreToolUse[0]' "$update_target")"
foreign_two="$(jq -c '.hooks.PreToolUse[2]' "$update_target")"

# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --global
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$UPDATE_LOG"
  merge_hook_entries "${FIXTURES}/codex-hooks-changed-matcher.json" \
    "$update_target" "codex" "hook" "/opt/old/hooks"
) >/dev/null

assert_eq "$(jq -c '.hooks.PreToolUse[0]' "$update_target")" "$foreign_pre" \
  "an updated owned entry must leave the foreign group ahead of it unchanged"
assert_eq "$(jq -c '.hooks.PreToolUse[2]' "$update_target")" "$foreign_two" \
  "an updated owned entry must leave the foreign group behind it unchanged"
assert_eq "$(jq '.hooks.PreToolUse | length' "$update_target")" "3" \
  "an update must not append a second owned group"
assert_eq "$(jq -r '.hooks.PreToolUse[1].matcher' "$update_target")" "^(apply_patch|Bash|Edit)$" \
  "an update must rewrite the owned group in place with the new matcher"

# ---------------------------------------------------------------------------
# Item 5 and 13: a manifest listing an owned entry the shipped config no
# longer carries removes that entry, keeps the foreign groups, and leaves
# exactly one @entries: line for hooks.json[hooks].
# ---------------------------------------------------------------------------
REMOVE_HOME="${SCRATCH}/remove-home"
REMOVE_LOG="${SCRATCH}/remove-deploy.log"
mkdir -p "$REMOVE_HOME/.codex"
remove_target="${REMOVE_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":[
  {"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},
  {"matcher":"Retired","hooks":[{"type":"command","command":"/opt/retired/guard.sh"}]}
]}}' > "$remove_target"
printf '%s\t%s\t%s\t%s\t%s\n' \
  "${remove_target}[hooks]" codex hook plugins/ai_dev/hooks/codex-custom-deploy-hooks.json \
  '@entries:[{"event":"PreToolUse","identity":"/opt/retired/guard.sh"}]' > "$REMOVE_LOG"

HOME="$REMOVE_HOME" DEPLOYED_ARTIFACTS_LOG="$REMOVE_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex >/dev/null

assert_eq "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Retired")] | length' "$remove_target")" "0" \
  "a redeploy must remove an owned entry the shipped config no longer carries"
assert_eq "$(jq -r '.hooks.PreToolUse[0].matcher' "$remove_target")" "Foreign" \
  "a redeploy that removes an owned entry must keep the foreign group"
entries_lines="$(grep -c '@entries:' "$REMOVE_LOG" || true)"
assert_eq "$entries_lines" "1" "a redeploy must leave exactly one @entries: line for hooks.json[hooks]"
assert_eq "$(grep -c "${remove_target}\[hooks\]" "$REMOVE_LOG" || true)" "1" \
  "a redeploy must leave exactly one log line for hooks.json[hooks]"

# ---------------------------------------------------------------------------
# Item 10: a legacy whole-key prior on a hooks.json[hooks] line becomes an
# @entries: manifest after one deploy.
# ---------------------------------------------------------------------------
LEGACY_HOME="${SCRATCH}/legacy-home"
LEGACY_LOG="${SCRATCH}/legacy-deploy.log"
mkdir -p "$LEGACY_HOME/.codex"
legacy_target="${LEGACY_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' > "$legacy_target"
printf '%s\t%s\t%s\t%s\t%s\n' \
  "${legacy_target}[hooks]" codex hook plugins/ai_dev/hooks/codex-custom-deploy-hooks.json \
  '{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}' > "$LEGACY_LOG"

HOME="$LEGACY_HOME" DEPLOYED_ARTIFACTS_LOG="$LEGACY_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex >/dev/null

legacy_field="$(awk -F'\t' -v p="${legacy_target}[hooks]" '$1==p{print $5; exit}' "$LEGACY_LOG")"
case "$legacy_field" in
  @entries:*) ;;
  *) fail "a legacy whole-key prior must become an @entries: manifest, got: $legacy_field" ;;
esac

# ---------------------------------------------------------------------------
# Item 6: uninstall after the item 1 deploy keeps both foreign groups, removes
# ai-modules' group and its log line, reports the line removed rather than
# "still exists after removal", and leaves no empty hooks object when the file
# held no other hooks.
# ---------------------------------------------------------------------------
# Rebuild the item 1 state, then uninstall.
rm -f "$codex_hooks" "$GLOBAL_LOG"
printf '%s\n' '{"hooks":{
  "PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}],
  "PostToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-post"}]}]
}}' > "$codex_hooks"
deploy_global_codex >/dev/null

uninstall_out="$(deploy_global_codex --uninstall)"
assert_eq "$(jq -r '.hooks.PreToolUse[0].matcher' "$codex_hooks")" "Foreign" \
  "uninstall must keep the foreign PreToolUse group"
assert_eq "$(jq -r '.hooks.PostToolUse[0].matcher' "$codex_hooks")" "Foreign" \
  "uninstall must keep the foreign PostToolUse group"
assert_eq "$(jq '.hooks.PreToolUse | length' "$codex_hooks")" "1" \
  "uninstall must remove ai-modules' group"
if grep -q 'still exists after removal' <<< "$uninstall_out"; then
  fail "uninstall must report its line removed rather than 'still exists after removal': $uninstall_out"
fi
printf '%s\n' "$uninstall_out" | grep -q 'removed.*hooks\.json\[hooks\]' ||
  fail "uninstall must report the hooks.json[hooks] line removed, got: $uninstall_out"
if grep -q "${codex_hooks}\[hooks\]" "$GLOBAL_LOG" 2>/dev/null; then
  fail "uninstall must drop the hooks.json[hooks] log line"
fi

# A file that held no other hooks leaves no empty hooks object behind.
EMPTY_HOME="${SCRATCH}/empty-home"
EMPTY_LOG="${SCRATCH}/empty-deploy.log"
mkdir -p "$EMPTY_HOME/.codex"
HOME="$EMPTY_HOME" DEPLOYED_ARTIFACTS_LOG="$EMPTY_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex >/dev/null
HOME="$EMPTY_HOME" DEPLOYED_ARTIFACTS_LOG="$EMPTY_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex --uninstall >/dev/null
if jq -e 'has("hooks")' "${EMPTY_HOME}/.codex/hooks.json" >/dev/null 2>&1; then
  fail "uninstall must leave no empty hooks object behind"
fi

# ---------------------------------------------------------------------------
# Item 7: the entry-merge function on a staged Cursor fixture keeps the foreign
# event list, its entry, and the top-level version, adds ai-modules' entry
# once, and the manifest uninstall removes only that entry.
# ---------------------------------------------------------------------------
CURSOR_APP="${SCRATCH}/cursor-app"
CURSOR_LOG="${SCRATCH}/cursor-deploy.log"
mkdir -p "$CURSOR_APP"
cursor_target="${CURSOR_APP}/hooks.json"
printf '%s\n' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"/bin/foreign-shell","other":true}]}}' \
  > "$cursor_target"

# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$CURSOR_LOG"
  merge_hook_entries "${FIXTURES}/cursor-hooks.json" "$cursor_target" "cursor" "hook" "${CURSOR_APP}/hooks"
) >/dev/null

assert_eq "$(jq -c '.version' "$cursor_target")" "1" \
  "the Cursor entry merge must keep the top-level version"
assert_eq "$(jq -c '.hooks.beforeShellExecution[0]' "$cursor_target")" \
  '{"command":"/bin/foreign-shell","other":true}' \
  "the Cursor entry merge must keep the foreign entry unchanged"
assert_eq "$(jq '.hooks.beforeShellExecution | length' "$cursor_target")" "2" \
  "the Cursor entry merge must add ai-modules' entry exactly once"
assert_eq "$(jq -r '.hooks.beforeShellExecution[1].command' "$cursor_target")" \
  "${CURSOR_APP}/hooks/charter_guardrail.sh" \
  "the Cursor entry merge must rewrite the owned entry's ./hooks/ command"

# A second identical call is a no-op.
cp "$cursor_target" "${SCRATCH}/cursor-after-first.json"
# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$CURSOR_LOG"
  merge_hook_entries "${FIXTURES}/cursor-hooks.json" "$cursor_target" "cursor" "hook" "${CURSOR_APP}/hooks"
) >/dev/null
cmp -s "${SCRATCH}/cursor-after-first.json" "$cursor_target" ||
  fail "a second Cursor entry merge must leave hooks.json byte-identical"

# The manifest uninstall removes only ai-modules' entry.
# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$CURSOR_LOG"
  uninstall_logged_artifacts
) >/dev/null

assert_eq "$(jq -c '.version' "$cursor_target")" "1" \
  "the Cursor manifest uninstall must keep the top-level version"
assert_eq "$(jq -c '.hooks.beforeShellExecution' "$cursor_target")" \
  '[{"command":"/bin/foreign-shell","other":true}]' \
  "the Cursor manifest uninstall must remove only ai-modules' entry"

# ---------------------------------------------------------------------------
# Item 8: the entry-merge function on a staged Claude Code fixture keeps a
# foreign hook group and an unrelated settings key, and adds ai-modules' group
# once.
# ---------------------------------------------------------------------------
CLAUDE_APP="${SCRATCH}/claude-app"
CLAUDE_LOG="${SCRATCH}/claude-deploy.log"
mkdir -p "$CLAUDE_APP"
claude_target="${CLAUDE_APP}/settings.json"
printf '%s\n' '{"outputStyle":"keep-me","hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-claude"}]}]}}' \
  > "$claude_target"

# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$CLAUDE_LOG"
  merge_hook_entries "${FIXTURES}/claude-code-hooks.json" "$claude_target" "claude" "hook" "${CLAUDE_APP}/hooks"
) >/dev/null

assert_eq "$(jq -r '.outputStyle' "$claude_target")" "keep-me" \
  "the Claude entry merge must keep an unrelated settings key"
assert_eq "$(jq -c '.hooks.PreToolUse[0]' "$claude_target")" \
  '{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-claude"}]}' \
  "the Claude entry merge must keep the foreign hook group unchanged"
assert_eq "$(jq '.hooks.PreToolUse | length' "$claude_target")" "2" \
  "the Claude entry merge must add ai-modules' group exactly once"

# The manifest uninstall removes only ai-modules' group.
# The assignments below configure the sourced deployment.sh; shellcheck
# cannot see their use through `source=/dev/null`.
# shellcheck disable=SC2034
(
  set -- --uninstall
  DEPLOYMENT_SH_SKIP_MAIN=1
  # shellcheck source=/dev/null
  source "$DEPLOY_SCRIPT"
  DRY_RUN=false
  DEPLOYED_ARTIFACTS_LOG="$CLAUDE_LOG"
  uninstall_logged_artifacts
) >/dev/null

assert_eq "$(jq '.hooks.PreToolUse | length' "$claude_target")" "1" \
  "the Claude manifest uninstall must remove only ai-modules' group"
assert_eq "$(jq -r '.outputStyle' "$claude_target")" "keep-me" \
  "the Claude manifest uninstall must keep an unrelated settings key"

# ---------------------------------------------------------------------------
# Item 11: the routing is the entry merge, not a copy and not a whole-key
# merge. The cursor arm's cursor-hooks route calls merge_hook_entries with no
# copy_file for it, and neither the codex nor the claude arm passes "hooks" to
# merge_json_key.
# ---------------------------------------------------------------------------
if grep -Fq 'merge_json_key "$source_abs" "${app_dir}/hooks.json" "hooks"' "$DEPLOY_SCRIPT"; then
  fail "the codex arm must not pass \"hooks\" to merge_json_key"
fi
if grep -Fq 'merge_json_key "$source_abs" "${app_dir}/settings.json" "hooks"' "$DEPLOY_SCRIPT"; then
  fail "the claude arm must not pass \"hooks\" to merge_json_key"
fi
grep -Fq 'merge_hook_entries "$source_abs" "${app_dir}/hooks.json" "$app_id" "$type" "$hooks_dir"' "$DEPLOY_SCRIPT" ||
  fail "the cursor and codex arms must route their hook config through merge_hook_entries"

cursor_arm="$(awk '/^        cursor\)$/{in_arm=1} in_arm && /^        [a-z|]+\)$/{if (seen) exit; seen=1} in_arm{print}' "$DEPLOY_SCRIPT")"
printf '%s\n' "$cursor_arm" | grep -Fq 'merge_hook_entries' ||
  fail "the cursor arm's cursor-hooks route must call the entry-merge function"
if printf '%s\n' "$cursor_arm" | grep -Fq 'copy_file "$source_abs" "$dest_path"'; then
  fail "the cursor arm must not copy a cursor-hooks config with copy_file"
fi

# ---------------------------------------------------------------------------
# Item 12: deployment/README.md describes the entry merge and the @entries:
# manifest, and no longer describes a Cursor hook-config copy or a whole-key
# hooks merge.
# ---------------------------------------------------------------------------
README="${REPO_ROOT}/deployment/README.md"
assert_file "$README"

# Each target's hook wording is read from its own table row, in both tables, so
# a row stripped of the entry merge cannot stay green on wording that survives
# elsewhere in the file. The Target Layout row leads with the target label; the
# Generated Output row leads with its hook source type and carries the target
# in its second cell.
readme_hook_rows() { # path -> one "label<TAB>table<TAB>row" line per target
  local path="$1" label row
  for label in 'Cursor' 'Claude Code' 'OpenAI Codex'; do
    row="$(grep -E "^\\| ${label} \\|" "$path" | head -n 1 || true)"
    printf '%s\t%s\t%s\n' "$label" 'Target Layout' "$row"
    row="$(grep -E "^\\| hook \\([^|]*\\) \\| ${label} \\|" "$path" | head -n 1 || true)"
    printf '%s\t%s\t%s\n' "$label" 'Generated Output' "$row"
  done
}

readme_problems() { # path -> one problem line per failed assertion
  local path="$1" label table row problems=""
  while IFS=$'\t' read -r label table row; do
    if [[ -z "$row" ]]; then
      problems+="missing the ${label} hook row in the ${table} table"$'\n'
    elif ! printf '%s\n' "$row" | grep -Eq 'entry merge|entry by entry|entry-grain|entries merged|merged one by one'; then
      problems+="the ${table} ${label} hook row must state the entry merge"$'\n'
    fi
  done < <(readme_hook_rows "$path")
  if grep -Fq 'copy from `cursor-hooks*.json`' "$path"; then
    problems+="the Cursor hook row must not say the config is copied to ~/.cursor/hooks.json"$'\n'
  fi
  if grep -Fq 'copied to `~/.cursor/hooks.json`' "$path"; then
    problems+="the Cursor hook row must not say the config is copied to ~/.cursor/hooks.json"$'\n'
  fi
  if grep -Fq '`hooks` key merged into' "$path"; then
    problems+="the hook rows must not say the hooks key is merged whole"$'\n'
  fi
  if grep -Fq '`.hooks` key merged into' "$path"; then
    problems+="the hook rows must not say the .hooks key is merged whole"$'\n'
  fi
  printf '%s' "$problems"
}

readme_out="$(readme_problems "$README")"
if [[ -n "$readme_out" ]]; then
  fail "deployment/README.md does not describe the entry merge in every hook row:"$'\n'"$readme_out"
fi
grep -Fq '@entries:' "$README" ||
  fail "deployment/README.md must describe the @entries: manifest in the fifth-field passage"

# ---------------------------------------------------------------------------
# Item 14: no live wiki page still states the whole-key hook merge, and no page
# states the entry merge writes Antigravity's hook configuration. wiki/raw/ and
# wiki/log.md stay out of the sweep. Sentences are read with wraps collapsed, so
# a wrap falling mid-phrase does not hide a claim, and each claim is anchored to
# its subject: the sentence must also speak about hook configuration, which
# keeps the scalar-key wording about settings keys out of the sweep.
# ---------------------------------------------------------------------------
wiki_scan() { # wiki-root -> one problem line per superseded claim
  python3 - "$1" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
# Every wording the task names for a whole-key hook merge, plus the phrasings
# its live pages carried before the rewrite: the merge named on
# "hook-configuration", the same claim as "merges hook configuration as a JSON
# key", and a whole-`hooks`-key write spelled "hook configuration under the
# `hooks` key".
claim = re.compile(
    r"merged as a JSON key|merges hook configuration as a JSON key"
    r"|JSON key merge|key-merge function|hook merges|hook-configuration merges"
    r"|whole `hooks` key|whole hooks key|hooks key is merged"
    r"|hook configuration under the `hooks` key",
    re.IGNORECASE,
)
subject = re.compile(r"\bhook", re.IGNORECASE)
entry_merge = re.compile(r"entry merge|entry by entry|entry-grain", re.IGNORECASE)
antigravity = re.compile(r"antigravity", re.IGNORECASE)
# A sentence that states the Antigravity route alongside the entry merge keeps
# its named-key carve-out, which is the correct claim rather than a violation.
antigravity_carve_out = re.compile(
    r"named-key|named-hook|charter_guardrail", re.IGNORECASE
)

problems = []
for path in sorted(root.rglob("*.md")):
    rel = path.relative_to(root)
    if rel.parts[0] == "raw" or rel.name == "log.md":
        continue
    text = re.sub(r"\s+", " ", path.read_text(encoding="utf-8"))
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if claim.search(sentence) and subject.search(sentence):
            problems.append(f"{rel}: whole-key hook-merge claim: {sentence.strip()}")
        if (
            entry_merge.search(sentence)
            and antigravity.search(sentence)
            and not antigravity_carve_out.search(sentence)
        ):
            problems.append(
                f"{rel}: entry merge claimed for Antigravity: {sentence.strip()}"
            )
print("\n".join(problems))
PY
}

wiki_scan_out="$(wiki_scan "${REPO_ROOT}/wiki")"
if [[ -n "$wiki_scan_out" ]]; then
  fail "a live wiki page still carries a superseded hook-merge claim:"$'\n'"$wiki_scan_out"
fi

# The sweep proves its own fail branch: a copy of the wiki carrying all seven
# pre-change sentences the task names reports every one of them, so a scan that
# cannot fail on a named sentence fails here instead of passing silently.
PRE_CHANGE_WIKI="${SCRATCH}/pre-change-wiki"
mkdir -p "${PRE_CHANGE_WIKI}/concepts" "${PRE_CHANGE_WIKI}/raw"
printf '%s\n' \
  '# Deployment model' \
  '' \
  'The hook configuration is merged as a JSON key into an existing settings file.' \
  '' \
  'The hook-configuration merges on Claude, Codex, and Antigravity gain the same restore.' \
  > "${PRE_CHANGE_WIKI}/concepts/deployment-model.md"
printf '%s\n' \
  '# Hook delivery design' \
  '' \
  'It merges the Codex config-layer file into that harness'"'"'s own hook configuration under the `hooks` key.' \
  '' \
  'The deployment model'"'"'s key-merge function writes the Codex and Antigravity hook configuration.' \
  > "${PRE_CHANGE_WIKI}/concepts/hook-delivery-design.md"
printf '%s\n' \
  '# Hook surface portability' \
  '' \
  'The deployment model merges hook configuration as a JSON key rather than replacing the target file.' \
  > "${PRE_CHANGE_WIKI}/concepts/hook-surface-portability.md"
printf '%s\n' \
  '# Output style delivery design' \
  '' \
  'The marked block is the Markdown counterpart of the JSON key merge the script already performs for hook configuration.' \
  '' \
  'The hook merges that predate this work inherited the restore too.' \
  > "${PRE_CHANGE_WIKI}/concepts/output-style-delivery-design.md"
# A raw source and the log keep their text: the sweep must not read them.
printf '%s\n' 'The hook configuration is merged as a JSON key.' > "${PRE_CHANGE_WIKI}/raw/source.md"
printf '%s\n' 'The hook configuration is merged as a JSON key.' > "${PRE_CHANGE_WIKI}/log.md"

pre_change_out="$(wiki_scan "$PRE_CHANGE_WIKI")"
pre_change_hits="$(printf '%s\n' "$pre_change_out" | grep -c 'whole-key hook-merge claim' || true)"
assert_eq "$pre_change_hits" "7" \
  "the wiki sweep must report all seven named pre-change sentences, got: $pre_change_out"
if printf '%s\n' "$pre_change_out" | grep -Eq 'raw/source\.md|log\.md'; then
  fail "the wiki sweep must keep wiki/raw/ and wiki/log.md out of the scan: $pre_change_out"
fi

# ---------------------------------------------------------------------------
# Item 15: a hook file whose shape the merge does not own is foreign content.
# A `hooks` value that is not an object, or an event value that is not an array
# of objects, is left exactly as it was, and the deploy still succeeds so the
# remaining artifacts land. Reading such a shape as entries used to fail jq and
# abort the whole deploy.
# ---------------------------------------------------------------------------
malformed_deploy() { # home-dir -> runs a global Codex hook deploy in that home
  local home="$1"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex >/dev/null 2>&1
}

# A `hooks` value that is an object but not an entry map: every event's value is
# a non-array, so no event is mergeable and the whole value stays untouched.
NONLIST_HOME="${SCRATCH}/nonlist-home"
mkdir -p "${NONLIST_HOME}/.codex"
nonlist_target="${NONLIST_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":{"matcher":"x"},"PostToolUse":"hand-edited"}}' > "$nonlist_target"
malformed_deploy "$NONLIST_HOME" ||
  fail "a deploy must succeed over a hooks object whose event values are not arrays"
assert_eq "$(jq -c '.hooks' "$nonlist_target")" \
  '{"PreToolUse":{"matcher":"x"},"PostToolUse":"hand-edited"}' \
  "a deploy must leave a hooks object of non-array event values untouched"

# A `hooks` value that is an array rather than an object is preserved whole.
ARRAY_HOME="${SCRATCH}/array-home"
mkdir -p "${ARRAY_HOME}/.codex"
array_target="${ARRAY_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":[{"matcher":"x"}]}' > "$array_target"
malformed_deploy "$ARRAY_HOME" ||
  fail "a deploy must succeed over a hooks value that is an array"
assert_eq "$(jq -c '.hooks' "$array_target")" '[{"matcher":"x"}]' \
  "a deploy must leave a non-object hooks value untouched"

# A `hooks` value that is a string is preserved whole, and the top-level keys
# beside it stay as they were.
STRING_HOME="${SCRATCH}/string-home"
mkdir -p "${STRING_HOME}/.codex"
string_target="${STRING_HOME}/.codex/hooks.json"
printf '%s\n' '{"other":1,"hooks":"hand-edited"}' > "$string_target"
malformed_deploy "$STRING_HOME" ||
  fail "a deploy must succeed over a hooks value that is a string"
assert_eq "$(jq -c '.' "$string_target")" '{"other":1,"hooks":"hand-edited"}' \
  "a deploy must leave a non-object hooks value and its sibling keys untouched"

# A single non-array event value beside a mergeable one is preserved in place
# while the mergeable event takes ai-modules' entry.
MIXED_HOME="${SCRATCH}/mixed-home"
mkdir -p "${MIXED_HOME}/.codex"
mixed_target="${MIXED_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{
  "PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}],
  "PostToolUse":"hand-edited"
}}' > "$mixed_target"
mixed_foreign="$(jq -c '.hooks.PreToolUse[0]' "$mixed_target")"
malformed_deploy "$MIXED_HOME" ||
  fail "a deploy must succeed over a non-array event value beside a mergeable one"
assert_eq "$(jq -c '.hooks.PostToolUse' "$mixed_target")" '"hand-edited"' \
  "a deploy must leave a non-array event value untouched"
assert_eq "$(jq -c '.hooks.PreToolUse[0]' "$mixed_target")" "$mixed_foreign" \
  "a deploy must keep the foreign entry of a mergeable event"
assert_eq "$(jq '[.hooks.PreToolUse[] | select([.hooks[]?.command] | map(select(endswith("charter_guardrail.sh"))) | length > 0)] | length' "$mixed_target")" "1" \
  "a deploy must still add ai-modules' entry to a mergeable event beside a foreign one"

# A null hooks value carries no foreign content, so the merge treats it as
# absent and installs ai-modules' entry as on a file that lacks the key.
NULL_HOME="${SCRATCH}/null-home"
mkdir -p "${NULL_HOME}/.codex"
null_target="${NULL_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":null}' > "$null_target"
malformed_deploy "$NULL_HOME" ||
  fail "a deploy must succeed over a null hooks value"
assert_eq "$(jq '[.hooks.PreToolUse[] | select([.hooks[]?.command] | map(select(endswith("charter_guardrail.sh"))) | length > 0)] | length' "$null_target")" "1" \
  "a deploy must install ai-modules' entry into a null hooks value"

# An entry list that carries a non-object member is not an entry list either:
# the whole event value stays as it was.
JUNK_HOME="${SCRATCH}/junk-home"
mkdir -p "${JUNK_HOME}/.codex"
junk_target="${JUNK_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":[
  {"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]},
  "hand-edited"
]}}' > "$junk_target"
junk_before="$(jq -c '.hooks' "$junk_target")"
malformed_deploy "$JUNK_HOME" ||
  fail "a deploy must succeed over an event list holding a non-object member"
assert_eq "$(jq -c '.hooks' "$junk_target")" "$junk_before" \
  "a deploy must leave an event list with a non-object member untouched"

# A non-object hooks value does not block the artifacts after it: the hook
# script that follows the config in the deploy order still lands.
assert_file "${NONLIST_HOME}/.codex/hooks/charter_guardrail.sh"

# ---------------------------------------------------------------------------
# Item 16: the uninstall reads a value the deploy did not own as content it
# leaves alone. A hooks value the deploy recorded as an empty @entries: manifest
# and a non-object hooks value both survive the uninstall, which never deletes
# a key the deploy did not write.
# ---------------------------------------------------------------------------
uninstall_in_home() { # home-dir -> runs a global Codex hook uninstall there
  local home="$1"
  HOME="$home" DEPLOYED_ARTIFACTS_LOG="${home}/deploy.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type hook --target codex --uninstall
}

# A hooks value that is an empty list is not an entry map, so the deploy owns
# no entry there and records an empty manifest; the uninstall must leave the
# empty list in place instead of deleting the key.
EMPTY_LIST_HOME="${SCRATCH}/empty-list-home"
mkdir -p "${EMPTY_LIST_HOME}/.codex"
empty_list_target="${EMPTY_LIST_HOME}/.codex/hooks.json"
printf '%s\n' '{"version":1,"hooks":[]}' > "$empty_list_target"
malformed_deploy "$EMPTY_LIST_HOME" ||
  fail "a deploy must succeed over an empty hooks list"
grep -q "@entries:\[\]" "${EMPTY_LIST_HOME}/deploy.log" ||
  fail "a deploy over an empty hooks list must record an empty @entries: manifest"
uninstall_in_home "$EMPTY_LIST_HOME" >/dev/null ||
  fail "an uninstall must succeed after a deploy over an empty hooks list"
assert_eq "$(jq -c '.' "$empty_list_target")" '{"version":1,"hooks":[]}' \
  "an uninstall must leave an empty hooks list exactly as the deploy found it"

# An event value that is an object is not an entry list either: the uninstall
# skips it, reports its line removed, and leaves the value untouched.
FOREIGN_OBJ_HOME="${SCRATCH}/foreign-obj-home"
mkdir -p "${FOREIGN_OBJ_HOME}/.codex"
foreign_obj_target="${FOREIGN_OBJ_HOME}/.codex/hooks.json"
printf '%s\n' '{"version":1,"hooks":{"PreToolUse":{"matcher":"x"}}}' > "$foreign_obj_target"
malformed_deploy "$FOREIGN_OBJ_HOME" ||
  fail "a deploy must succeed over an object event value"
uninstall_in_home "$FOREIGN_OBJ_HOME" >/dev/null ||
  fail "an uninstall must succeed after a deploy over an object event value"
assert_eq "$(jq -c '.' "$foreign_obj_target")" '{"version":1,"hooks":{"PreToolUse":{"matcher":"x"}}}' \
  "an uninstall must leave an object event value exactly as the deploy found it"

# A non-object hooks value survives the uninstall with its sibling keys.
FOREIGN_VALUE_HOME="${SCRATCH}/foreign-value-home"
mkdir -p "${FOREIGN_VALUE_HOME}/.codex"
foreign_value_target="${FOREIGN_VALUE_HOME}/.codex/hooks.json"
printf '%s\n' '{"other":1,"hooks":"hand-edited"}' > "$foreign_value_target"
malformed_deploy "$FOREIGN_VALUE_HOME" ||
  fail "a deploy must succeed over a non-object hooks value"
uninstall_in_home "$FOREIGN_VALUE_HOME" >/dev/null ||
  fail "an uninstall must succeed after a deploy over a non-object hooks value"
assert_eq "$(jq -c '.' "$foreign_value_target")" '{"other":1,"hooks":"hand-edited"}' \
  "an uninstall must leave a non-object hooks value and its sibling keys untouched"

# ---------------------------------------------------------------------------
# Item 17: a hand-edited event value beside a mergeable one is content the
# uninstall does not own, so the uninstall skips it, removes ai-modules' entry
# from the mergeable event, reports the line removed rather than failed, and
# drops its log line.
# ---------------------------------------------------------------------------
FOREIGN_EVENT_HOME="${SCRATCH}/foreign-event-home"
mkdir -p "${FOREIGN_EVENT_HOME}/.codex"
foreign_event_target="${FOREIGN_EVENT_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{
  "PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}],
  "PostToolUse":"hand-edited"
}}' > "$foreign_event_target"
malformed_deploy "$FOREIGN_EVENT_HOME" ||
  fail "a deploy must succeed over a non-array event value beside a mergeable one"
foreign_event_out="$(uninstall_in_home "$FOREIGN_EVENT_HOME")" ||
  fail "an uninstall must succeed over a non-array event value beside a mergeable one"
assert_eq "$(jq -c '.hooks.PostToolUse' "$foreign_event_target")" '"hand-edited"' \
  "an uninstall must leave a non-array event value untouched"
assert_eq "$(jq -c '.hooks.PreToolUse' "$foreign_event_target")" \
  '[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]' \
  "an uninstall must remove ai-modules' entry from a mergeable event beside a foreign one"
if grep -q 'still exists after removal' <<< "$foreign_event_out"; then
  fail "an uninstall beside a non-array event value must report its line removed: $foreign_event_out"
fi
printf '%s\n' "$foreign_event_out" | grep -q 'removed.*hooks\.json\[hooks\]' ||
  fail "an uninstall beside a non-array event value must report the line removed, got: $foreign_event_out"
if grep -q 'hooks\.json\[hooks\]' "${FOREIGN_EVENT_HOME}/deploy.log" 2>/dev/null; then
  fail "an uninstall beside a non-array event value must drop the hooks.json[hooks] log line"
fi

# Item 18: an event value that became foreign while still holding an entry the
# recorded manifest names is not read as wholly unowned. The deploy keeps the
# entry in its manifest so a later uninstall still owns it, and the uninstall
# reports failure rather than claiming a removal it did not make. An event
# replaced wholesale holds no owned entry, so it keeps round 2's clean success.
# ---------------------------------------------------------------------------
# The identity the deploy recorded for its own entry in a destination's
# @entries: manifest, read from the log so a foreign entry in the same file
# cannot be mistaken for it.
manifest_identity() { # home-dir -> identity string
  awk -F'\t' '$1 ~ /hooks\.json\[hooks\]$/ {print $5}' "$1/deploy.log" | tail -1 \
    | sed -e 's/^@entries://' \
    | jq -r '.[0].identity // ""' 2>/dev/null
}

owned_entry_present() { # hooks.json identity -> "true" when the entry is there
  jq -r --arg id "$2" '
    [.hooks[]?[]? | select(type == "object")
     | [.hooks[]? | (.command // empty)] | unique | sort | join("\u0001")
     | select(. == $id)] | length' "$1"
}

# A redeploy over an appended non-object member must keep the owned entry in
# the manifest instead of rewriting it to @entries:[].
PARTIAL_HOME="${SCRATCH}/partial-foreign-home"
mkdir -p "${PARTIAL_HOME}/.codex"
partial_target="${PARTIAL_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' \
  > "$partial_target"
malformed_deploy "$PARTIAL_HOME" ||
  fail "a deploy must succeed into a file holding one foreign group"
partial_identity="$(manifest_identity "$PARTIAL_HOME")"
[[ -n "$partial_identity" ]] ||
  fail "the deploy must record the identity of the entry it installed"
jq '.hooks.PreToolUse += ["hand-edited"]' "$partial_target" > "${PARTIAL_HOME}/tmp" \
  && mv "${PARTIAL_HOME}/tmp" "$partial_target"
malformed_deploy "$PARTIAL_HOME" ||
  fail "a redeploy must succeed over an event value that holds a non-object member"
partial_manifest="$(awk -F'\t' '$1 ~ /hooks\.json\[hooks\]$/ {print $5}' "${PARTIAL_HOME}/deploy.log" | tail -1)"
[[ "$partial_manifest" == *"$partial_identity"* ]] ||
  fail "a redeploy must keep an owned entry its event value still holds, got: $partial_manifest"

# An uninstall over that same value must not claim a removal it did not make,
# and must not delete the script the surviving entry points at.
partial_out="$(uninstall_in_home "$PARTIAL_HOME")" || true
if grep -q 'removed.*hooks\.json\[hooks\]' <<< "$partial_out"; then
  fail "an uninstall must not report a removal over an entry it left in place: $partial_out"
fi
assert_eq "$(owned_entry_present "$partial_target" "$partial_identity")" "1" \
  "an uninstall must leave the owned entry it could not remove"
[[ -f "${PARTIAL_HOME}/.codex/hooks/charter_guardrail.sh" ]] ||
  fail "an uninstall must keep a hook script a surviving owned entry references"
grep -q "$partial_identity" "${PARTIAL_HOME}/deploy.log" ||
  fail "an uninstall must keep the log line of an entry it left in place"

# An event replaced wholesale holds no owned entry, so the uninstall reports
# success, drops its line, and preserves the user's value: round 2's behaviour.
WHOLE_HOME="${SCRATCH}/whole-foreign-home"
mkdir -p "${WHOLE_HOME}/.codex"
whole_target="${WHOLE_HOME}/.codex/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Foreign","hooks":[{"type":"command","command":"/bin/foreign-pre"}]}]}}' \
  > "$whole_target"
malformed_deploy "$WHOLE_HOME" ||
  fail "a deploy must succeed before a wholesale event replacement"
jq '.hooks.PreToolUse = "hand-edited"' "$whole_target" > "${WHOLE_HOME}/tmp" \
  && mv "${WHOLE_HOME}/tmp" "$whole_target"
whole_out="$(uninstall_in_home "$WHOLE_HOME")" ||
  fail "an uninstall must succeed over a wholesale event replacement"
if grep -q 'still exists after removal' <<< "$whole_out"; then
  fail "a wholesale replacement must not report failure: $whole_out"
fi
assert_eq "$(jq -c '.hooks.PreToolUse' "$whole_target")" '"hand-edited"' \
  "an uninstall must preserve a wholesale event replacement"

printf 'Hook entry-merge regression passed\n'
