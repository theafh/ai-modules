#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
DEPLOY_LOG="${REPO_ROOT}/deployment/deployed_artefacts.log"
FIXTURE_PLUGIN="${REPO_ROOT}/plugins/__opencode_deploy_test"
BYTECODE_PLUGIN="${REPO_ROOT}/plugins/__bytecode_deploy_test"
SCRATCH="$(mktemp -d)"
PROJECT_DIR="${SCRATCH}/project"
BYTECODE_PROJECT_DIR="${SCRATCH}/bytecode-project"
HOME_DIR="${SCRATCH}/home"
LOG_BACKUP="${SCRATCH}/deployed_artefacts.log.backup"
LOG_HAD_FILE=false

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
  [[ ! -L "$1" ]] || fail "expected real file, got symlink: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "expected directory: $1"
  [[ ! -L "$1" ]] || fail "expected real directory, got symlink: $1"
}

assert_contains() {
  local path="$1" pattern="$2"
  grep -Eq -- "$pattern" "$path" || fail "expected $path to contain pattern: $pattern"
}

assert_not_contains() {
  local path="$1" pattern="$2"
  if grep -Eq -- "$pattern" "$path"; then
    fail "expected $path not to contain pattern: $pattern"
  fi
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# Full recursive listing plus per-file checksums, both relative to the tree
# root, so two trees at different paths compare byte-for-byte.
snapshot_tree() {
  local root="$1" rel=""
  (
    cd "$root" || exit 1
    find . | LC_ALL=C sort
    find . -type f | LC_ALL=C sort | while IFS= read -r rel; do
      printf '%s  %s\n' "$(sha256_of "$rel")" "$rel"
    done
  )
}

assert_no_bytecode() {
  local root="$1"
  local hits
  hits="$(find "$root" \( -type d -name '__pycache__' -o -type f -name '*.pyc' \) -print)"
  [[ -z "$hits" ]] || fail "expected no Python bytecode under $root, found:"$'\n'"$hits"
}

cleanup() {
  if [[ "$LOG_HAD_FILE" == true ]]; then
    mv "$LOG_BACKUP" "$DEPLOY_LOG"
  else
    rm -f "$DEPLOY_LOG"
  fi
  rm -rf "$SCRATCH" "$FIXTURE_PLUGIN" "$BYTECODE_PLUGIN"
}
trap cleanup EXIT

cd "$REPO_ROOT"

if [[ -f "$DEPLOY_LOG" ]]; then
  LOG_HAD_FILE=true
  cp "$DEPLOY_LOG" "$LOG_BACKUP"
fi
rm -f "$DEPLOY_LOG"

mkdir -p "$PROJECT_DIR" "$HOME_DIR/.config/opencode" "$HOME_DIR/.gemini/config" "$FIXTURE_PLUGIN/commands"
cat > "$FIXTURE_PLUGIN/commands/opencode_fixture_command.md" <<'COMMAND'
# OpenCode Fixture Command

This command exists only while the OpenCode deployment regression test runs.
COMMAND

dry_run_output="$(HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --target opencode --global --dry-run)"
printf '%s\n' "$dry_run_output" | grep -q "${HOME_DIR}/.config/opencode" || fail "global dry-run did not resolve ~/.config/opencode"
printf '%s\n' "$dry_run_output" | grep -q "would-bak.*\.opencode-config" || fail "global dry-run did not use the OpenCode backup name override"
if printf '%s\n' "$dry_run_output" | grep -q "${HOME_DIR}/.opencode/"; then
  fail "global dry-run used ~/.opencode"
fi

antigravity_dry_run="$(HOME="$HOME_DIR" "$DEPLOY_SCRIPT" --target antigravity --global --dry-run)"
printf '%s\n' "$antigravity_dry_run" | grep -q "${HOME_DIR}/.gemini/config" ||
  fail "Antigravity global dry-run did not resolve ~/.gemini/config"
printf '%s\n' "$antigravity_dry_run" | grep -q "${HOME_DIR}/.gemini/config/skills/task" ||
  fail "Antigravity global dry-run missed config/skills fan-out"
printf '%s\n' "$antigravity_dry_run" | grep -q "${HOME_DIR}/.gemini/antigravity/skills/task" ||
  fail "Antigravity global dry-run missed IDE skills fan-out"
printf '%s\n' "$antigravity_dry_run" | grep -q "${HOME_DIR}/.gemini/antigravity-cli/skills/task" ||
  fail "Antigravity global dry-run missed CLI skills fan-out"
printf '%s\n' "$antigravity_dry_run" | grep -q "would-rewrite.*${HOME_DIR}/.gemini/config/hooks/" ||
  fail "Antigravity global dry-run did not rewrite hook commands to the global hooks dir"
if printf '%s\n' "$antigravity_dry_run" | grep -q "${HOME_DIR}/.gemini/antigravity/agents"; then
  fail "Antigravity global dry-run deployed agents under the IDE skill root"
fi

"$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target opencode >/dev/null

assert_dir "$PROJECT_DIR/.opencode/skills/task"
assert_file "$PROJECT_DIR/.opencode/skills/task/SKILL.md"
assert_file "$PROJECT_DIR/.opencode/commands/opencode_fixture_command.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_drift_task.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_reviewer_task.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_verifier_task.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md"

assert_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^mode: subagent$'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^model:'
assert_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^permission: \{ edit: deny \}$'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^tools:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^write:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^(name|version|background|effort|model_reasoning_effort):'

assert_contains "$PROJECT_DIR/.opencode/agents/auto_reviewer_task.md" '^permission: \{ edit: deny, bash: deny \}$'
assert_contains "$PROJECT_DIR/.opencode/agents/auto_verifier_task.md" '^permission: \{ edit: deny, bash: deny \}$'

assert_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^mode: subagent$'
assert_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^description:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^model:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^permission:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" 'edit: deny|bash: deny'

"$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target opencode --uninstall >/dev/null

[[ ! -e "$PROJECT_DIR/.opencode/skills/task" ]] || fail "uninstall left skill directory"
[[ ! -e "$PROJECT_DIR/.opencode/commands/opencode_fixture_command.md" ]] || fail "uninstall left fixture command"
[[ ! -e "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" ]] || fail "uninstall left agent file"

antigravity_project_out="${SCRATCH}/antigravity-project.out"
"$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target antigravity >"$antigravity_project_out"

assert_dir "$PROJECT_DIR/.agents/skills/task"
assert_file "$PROJECT_DIR/.agents/skills/task/SKILL.md"
assert_file "$PROJECT_DIR/.agents/agents/auto_drift_task.md"
assert_file "$PROJECT_DIR/.agents/agents/auto_reviewer_task.md"
assert_file "$PROJECT_DIR/.agents/agents/auto_verifier_task.md"
assert_file "$PROJECT_DIR/.agents/agents/auto_gate_task.md"
assert_file "$PROJECT_DIR/.agents/hooks/charter_guardrail.sh"
assert_file "$PROJECT_DIR/.agents/hooks.json"

grep -q 'Antigravity command workflow deployment is not supported' "$antigravity_project_out" ||
  fail "Antigravity command artifact should be explicitly skipped"
[[ ! -e "$PROJECT_DIR/.agents/commands" ]] || fail "Antigravity should not create a commands directory"
if grep -Fq $'\tantigravity\tcommand\t' "$DEPLOY_LOG"; then
  fail "Antigravity command skip should not be logged as a deployment"
fi

jq -e '.charter_guardrail.PreToolUse[] | select(.matcher == "*") | .hooks[] |
  select(.type == "command" and .command == ".agents/hooks/charter_guardrail.sh")' \
  "$PROJECT_DIR/.agents/hooks.json" >/dev/null ||
  fail "Antigravity project hooks.json should merge charter_guardrail with project-relative command"

assert_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" '^mainAgent: false$'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" '^subagent: true$'
assert_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" '^tools: \[view_file, grep_search, run_command\]$'
assert_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" '^commandExecutionPolicy: sandbox$'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" '^model:'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" '^(effort|version):'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_drift_task.md" 'read_file|edit_file|flash_lite'

assert_contains "$PROJECT_DIR/.agents/agents/auto_reviewer_task.md" '^mainAgent: false$'
assert_contains "$PROJECT_DIR/.agents/agents/auto_reviewer_task.md" '^tools: \[view_file, grep_search\]$'
assert_contains "$PROJECT_DIR/.agents/agents/auto_reviewer_task.md" '^commandExecutionPolicy: off$'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_reviewer_task.md" '^(effort|version):'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_reviewer_task.md" 'read_file|edit_file'

assert_contains "$PROJECT_DIR/.agents/agents/auto_verifier_task.md" '^commandExecutionPolicy: off$'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_verifier_task.md" '^(effort|version):'
assert_not_contains "$PROJECT_DIR/.agents/agents/auto_gate_task.md" '^tools:'
assert_contains "$PROJECT_DIR/.agents/agents/auto_gate_task.md" '^name: auto_gate_task$'
assert_contains "$PROJECT_DIR/.agents/agents/auto_gate_task.md" '^description:'

skill_log_count="$(grep -Fc "$PROJECT_DIR/.agents/skills/task"$'\t' "$DEPLOY_LOG")"
[[ "$skill_log_count" -eq 1 ]] || fail "expected one log line for shared .agents/skills/task, got $skill_log_count"
grep -F "$PROJECT_DIR/.agents/skills/task"$'\t' "$DEPLOY_LOG" | grep -Fq $'\tcodex\tskill\t' ||
  fail "shared .agents/skills/task should be logged under codex owner"

"$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target antigravity --uninstall >/dev/null
[[ ! -e "$PROJECT_DIR/.agents/agents/auto_drift_task.md" ]] || fail "Antigravity uninstall left agent file"
assert_dir "$PROJECT_DIR/.agents/skills/task"

"$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target codex --uninstall >/dev/null
[[ ! -e "$PROJECT_DIR/.agents/skills/task" ]] || fail "Codex uninstall should remove shared skill directory"

# ---------------------------------------------------------------------------
# Python bytecode exclusion.
#
# Two fixture skills carry byte-identical real files; one of them additionally
# carries the build residue a bundled Python script leaves behind — a
# scripts/__pycache__/ tree and a stray scripts/*.pyc outside it.
# ---------------------------------------------------------------------------
DIRTY_SRC="${BYTECODE_PLUGIN}/skills/__bytecode_dirty"
CLEAN_SRC="${BYTECODE_PLUGIN}/skills/__bytecode_clean"

mkdir -p "$DIRTY_SRC/scripts" "$CLEAN_SRC/scripts" "$BYTECODE_PROJECT_DIR"

for skill_dir in "$DIRTY_SRC" "$CLEAN_SRC"; do
  cat > "$skill_dir/SKILL.md" <<'SKILL'
---
name: bytecode_fixture
description: Fixture skill that exists only while the deployment bytecode regression test runs.
version: 1.0.0
---

# bytecode_fixture

This skill exists only while the deployment bytecode regression test runs.
SKILL
  cat > "$skill_dir/scripts/lint.py" <<'HELPER'
#!/usr/bin/env python3
"""Bundled helper standing in for a real skill script."""
print("fixture")
HELPER
done

mkdir -p "$DIRTY_SRC/scripts/__pycache__"
printf '\x00\x01fake-bytecode\n' > "$DIRTY_SRC/scripts/__pycache__/lint.cpython-314.pyc"
printf '\x00\x01fake-bytecode\n' > "$DIRTY_SRC/scripts/stray.pyc"

"$DEPLOY_SCRIPT" --project-dir "$BYTECODE_PROJECT_DIR" --target opencode --type skill >/dev/null

DIRTY_DEST="$BYTECODE_PROJECT_DIR/.opencode/skills/__bytecode_dirty"
CLEAN_DEST="$BYTECODE_PROJECT_DIR/.opencode/skills/__bytecode_clean"

# The bytecode-carrying source deploys its real files and nothing else.
assert_dir "$DIRTY_DEST"
assert_file "$DIRTY_DEST/SKILL.md"
assert_file "$DIRTY_DEST/scripts/lint.py"
assert_no_bytecode "$DIRTY_DEST"

# ... and lands byte-identical to the same skill deployed without residue.
diff <(snapshot_tree "$DIRTY_DEST") <(snapshot_tree "$CLEAN_DEST") ||
  fail "bytecode-carrying source did not deploy byte-identically to a clean source"

# The prune removes nothing else: a residue-free source round-trips exactly.
diff <(snapshot_tree "$CLEAN_SRC") <(snapshot_tree "$CLEAN_DEST") ||
  fail "residue-free skill destination diverged from its source"

# Already-shipped bytecode self-heals on the next deploy, with no migration pass.
mkdir -p "$DIRTY_DEST/scripts/__pycache__"
printf '\x00\x01stale-bytecode\n' > "$DIRTY_DEST/scripts/__pycache__/lint.cpython-314.pyc"
printf '\x00\x01stale-bytecode\n' > "$DIRTY_DEST/scripts/stale.pyc"

"$DEPLOY_SCRIPT" --project-dir "$BYTECODE_PROJECT_DIR" --target opencode --type skill >/dev/null

assert_file "$DIRTY_DEST/SKILL.md"
assert_no_bytecode "$DIRTY_DEST"
[[ ! -e "$DIRTY_DEST/scripts/stale.pyc" ]] || fail "redeploy left a stale .pyc in place"

printf 'OpenCode deployment regression passed\n'
printf 'Antigravity deployment regression passed\n'
printf 'Python bytecode exclusion regression passed\n'
