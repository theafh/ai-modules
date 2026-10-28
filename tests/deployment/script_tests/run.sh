#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
# Invoke the deploy script on the stock bash the floor targets.
DEPLOY_BASH="/bin/bash"
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

dry_run_output="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --target opencode --global --dry-run)"
printf '%s\n' "$dry_run_output" | grep -q "${HOME_DIR}/.config/opencode" || fail "global dry-run did not resolve ~/.config/opencode"
printf '%s\n' "$dry_run_output" | grep -q "would-bak.*\.opencode-config" || fail "global dry-run did not use the OpenCode backup name override"
if printf '%s\n' "$dry_run_output" | grep -q "${HOME_DIR}/.opencode/"; then
  fail "global dry-run used ~/.opencode"
fi

antigravity_dry_run="$(HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --target antigravity --global --dry-run)"
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

"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target opencode >/dev/null

assert_dir "$PROJECT_DIR/.opencode/skills/task"
assert_file "$PROJECT_DIR/.opencode/skills/task/SKILL.md"
assert_file "$PROJECT_DIR/.opencode/commands/opencode_fixture_command.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_drift_task.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_reviewer_task.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_verifier_task.md"
assert_file "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md"

assert_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^mode: subagent$'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^model:'
assert_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^permission:$'
assert_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^  edit: deny$'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^  bash: deny$'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^tools:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^write:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" '^(name|version|background|effort|model_reasoning_effort):'

for agent in auto_reviewer_task auto_verifier_task; do
  assert_contains "$PROJECT_DIR/.opencode/agents/$agent.md" '^permission:$'
  assert_contains "$PROJECT_DIR/.opencode/agents/$agent.md" '^  edit: deny$'
  assert_contains "$PROJECT_DIR/.opencode/agents/$agent.md" '^  bash: deny$'
done

assert_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^mode: subagent$'
assert_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^description:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^model:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" '^permission:'
assert_not_contains "$PROJECT_DIR/.opencode/agents/auto_shaper_task.md" 'edit: deny|bash: deny'

"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target opencode --uninstall >/dev/null

[[ ! -e "$PROJECT_DIR/.opencode/skills/task" ]] || fail "uninstall left skill directory"
[[ ! -e "$PROJECT_DIR/.opencode/commands/opencode_fixture_command.md" ]] || fail "uninstall left fixture command"
[[ ! -e "$PROJECT_DIR/.opencode/agents/auto_drift_task.md" ]] || fail "uninstall left agent file"

antigravity_project_out="${SCRATCH}/antigravity-project.out"
"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target antigravity >"$antigravity_project_out"

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

"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target antigravity --uninstall >/dev/null
[[ ! -e "$PROJECT_DIR/.agents/agents/auto_drift_task.md" ]] || fail "Antigravity uninstall left agent file"
assert_dir "$PROJECT_DIR/.agents/skills/task"

"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$PROJECT_DIR" --target codex --uninstall >/dev/null
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

"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$BYTECODE_PROJECT_DIR" --target opencode --type skill >/dev/null

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

"$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$BYTECODE_PROJECT_DIR" --target opencode --type skill >/dev/null

assert_file "$DIRTY_DEST/SKILL.md"
assert_no_bytecode "$DIRTY_DEST"
[[ ! -e "$DIRTY_DEST/scripts/stale.pyc" ]] || fail "redeploy left a stale .pyc in place"

# ---------------------------------------------------------------------------
# Backup copy skips sockets and FIFOs instead of aborting.
# ---------------------------------------------------------------------------
BACKUP_HOME="${SCRATCH}/backup-home"
mkdir -p "$BACKUP_HOME/.claude/kept dir"
printf 'keep\n' > "$BACKUP_HOME/.claude/kept dir/notes.txt"
printf 'target\n' > "$BACKUP_HOME/.claude/real.txt"
ln -s "real.txt" "$BACKUP_HOME/.claude/link.txt"
mkfifo "$BACKUP_HOME/.claude/live.pipe"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
  "$BACKUP_HOME/.claude/ipc.sock"

HOME="$BACKUP_HOME" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --target claude --type style >/dev/null

shopt -s nullglob
backup_dirs=("$BACKUP_HOME"/.claude_*)
shopt -u nullglob
[[ ${#backup_dirs[@]} -eq 1 ]] || fail "expected one ~/.claude_<timestamp> backup, got ${#backup_dirs[@]}"
bak="${backup_dirs[0]}"
assert_file "$bak/kept dir/notes.txt"
assert_contains "$bak/kept dir/notes.txt" '^keep$'
assert_file "$bak/real.txt"
[[ -L "$bak/link.txt" ]] || fail "backup dropped the symlink"
[[ "$(readlink "$bak/link.txt")" == "real.txt" ]] || fail "backup symlink target changed"
[[ ! -e "$bak/ipc.sock" ]] || fail "backup copied the socket"
[[ ! -p "$bak/live.pipe" && ! -e "$bak/live.pipe" ]] || fail "backup copied the FIFO"

# ---------------------------------------------------------------------------
# Backup copy accepts openrsync vanished-file exit 23 and Samba exit 24,
# and still fails a permission-shaped openrsync 23.
# ---------------------------------------------------------------------------
STUB_RSYNC_DIR="${SCRATCH}/rsync-stub"
mkdir -p "$STUB_RSYNC_DIR"
cat >"$STUB_RSYNC_DIR/rsync" <<'EOF'
#!/usr/bin/env bash
set +e
n=$#
offset=$((n - 1))
src="${@:$offset:1}"
dst="${@:$n:1}"
mkdir -p "$dst"
if [[ -d "$src" ]]; then
  cp -R "${src}." "$dst"
fi
case "${STUB_RSYNC_MODE:-}" in
  openrsync-vanished)
    printf '%s\n' 'rsync(12345): error: notes.txt: open (2) in .claude: No such file or directory' >&2
    exit 23
    ;;
  openrsync-denied)
    printf '%s\n' 'rsync(12345): error: secret: open (2) in .claude: Permission denied' >&2
    exit 23
    ;;
  samba-vanished)
    exit 24
    ;;
esac
exit 1
EOF
chmod +x "$STUB_RSYNC_DIR/rsync"

run_stub_backup_deploy() {
  local mode="$1"
  local home="$2"
  mkdir -p "$home/.claude"
  printf 'keep\n' >"$home/.claude/notes.txt"
  STUB_RSYNC_MODE="$mode" PATH="$STUB_RSYNC_DIR:$PATH" HOME="$home" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --target claude --type style
}

assert_one_claude_backup() {
  local home="$1"
  local backups
  shopt -s nullglob
  backups=("$home"/.claude_*)
  shopt -u nullglob
  [[ ${#backups[@]} -eq 1 ]] || fail "expected one backup under $home, got ${#backups[@]}"
  assert_file "${backups[0]}/notes.txt"
}

VANISH_HOME="${SCRATCH}/vanish-home"
run_stub_backup_deploy openrsync-vanished "$VANISH_HOME" >/dev/null
assert_one_claude_backup "$VANISH_HOME"

SAMBA_HOME="${SCRATCH}/samba-vanish-home"
run_stub_backup_deploy samba-vanished "$SAMBA_HOME" >/dev/null
assert_one_claude_backup "$SAMBA_HOME"

DENIED_HOME="${SCRATCH}/denied-home"
denied_rc=0
denied_out="$(run_stub_backup_deploy openrsync-denied "$DENIED_HOME" 2>&1)" || denied_rc=$?
[[ "$denied_rc" -ne 0 ]] || fail "permission-shaped openrsync 23 succeeded"
printf '%s\n' "$denied_out" | grep -Fq 'backup-copy' ||
  fail "permission-shaped openrsync 23 did not print backup-copy in: $denied_out"
printf '%s\n' "$denied_out" | grep -Fq 'rsync exited 23' ||
  fail "permission-shaped openrsync 23 did not name exit 23 in: $denied_out"

# ---------------------------------------------------------------------------
# Startup gate names jq, perl, and rsync when PATH lacks them.
# ---------------------------------------------------------------------------
link_cmd() {
  local dest_dir="$1" name="$2"
  ln -s "$(command -v "$name")" "$dest_dir/$name"
}

assert_startup_requires() {
  local missing="$1"
  shift
  local tool_dir out rc=0
  tool_dir="$(mktemp -d "${SCRATCH}/tools.XXXXXX")"
  link_cmd "$tool_dir" dirname
  local present
  for present in "$@"; do
    link_cmd "$tool_dir" "$present"
  done
  out="$(PATH="$tool_dir" HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --dry-run 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || fail "deploy dry-run succeeded without $missing"
  printf '%s\n' "$out" | grep -Fq "$missing is required for deployment" ||
    fail "missing $missing did not name $missing in: $out"
}

assert_startup_requires jq perl rsync
assert_startup_requires perl jq rsync
assert_startup_requires rsync jq perl

cleanup_tool_dir="$(mktemp -d "${SCRATCH}/cleanup-tools.XXXXXX")"
link_cmd "$cleanup_tool_dir" dirname
for extra in mkdir rm cat mktemp basename uname date sort mv; do
  link_cmd "$cleanup_tool_dir" "$extra"
done
cleanup_rc=0
cleanup_out="$(
  PATH="$cleanup_tool_dir" HOME="$HOME_DIR" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --clear-backups 2>&1
)" || cleanup_rc=$?
[[ "$cleanup_rc" -eq 0 ]] || fail "clear-backups without jq, perl, and rsync failed: $cleanup_out"
for gated in jq perl rsync; do
  if printf '%s\n' "$cleanup_out" | grep -Fq "$gated is required for deployment"; then
    fail "clear-backups still required $gated in: $cleanup_out"
  fi
done

# ---------------------------------------------------------------------------
# DEPLOYED_ARTIFACTS_LOG override and --only
# ---------------------------------------------------------------------------
only_home="${SCRATCH}/only-home"
only_log="${SCRATCH}/only-deployed.log"
mkdir -p "$only_home"
help_text="$("$DEPLOY_BASH" "$DEPLOY_SCRIPT" --help)"
printf '%s\n' "$help_text" | grep -Fq -- 'DEPLOYED_ARTIFACTS_LOG' ||
  fail "help text should name DEPLOYED_ARTIFACTS_LOG"
printf '%s\n' "$help_text" | grep -Fq -- '--only' ||
  fail "help text should name --only"
header_text="$(sed -n '1,60p' "$DEPLOY_SCRIPT")"
printf '%s\n' "$header_text" | grep -Fq -- 'DEPLOYED_ARTIFACTS_LOG' ||
  fail "header comment should name DEPLOYED_ARTIFACTS_LOG"
printf '%s\n' "$header_text" | grep -Fq -- '--only' ||
  fail "header comment should name --only"

log_before_sha=""
if [[ -f "$DEPLOY_LOG" ]]; then
  log_before_sha="$(sha256_of "$DEPLOY_LOG")"
fi
# No --type: --only alone must narrow every artefact type to the named set.
HOME="$only_home" DEPLOYED_ARTIFACTS_LOG="$only_log" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --target claude \
  --only language_humanizer,format_markdown >/dev/null
assert_file "$only_home/.claude/skills/language_humanizer/SKILL.md"
assert_file "$only_home/.claude/skills/format_markdown/SKILL.md"
# Three levels down covers every skill, agent, style, command, hook, settings
# file, and backup a global deploy writes, so the listing proves exactness.
only_listing="$(cd "$only_home" && find . -mindepth 1 -maxdepth 3 | LC_ALL=C sort | tr '\n' ' ')"
only_expected="./.claude ./.claude/skills ./.claude/skills/format_markdown ./.claude/skills/language_humanizer "
[[ "$only_listing" == "$only_expected" ]] ||
  fail "--only should deploy exactly the named skills, got: $only_listing"
assert_file "$only_log"
if [[ -n "$log_before_sha" ]]; then
  [[ "$(sha256_of "$DEPLOY_LOG")" == "$log_before_sha" ]] ||
    fail "DEPLOYED_ARTIFACTS_LOG override changed deployment/deployed_artefacts.log"
elif [[ -f "$DEPLOY_LOG" ]]; then
  fail "DEPLOYED_ARTIFACTS_LOG override created deployment/deployed_artefacts.log"
fi

# Uninstall reads the log and never --only, so the pair must abort before it
# removes anything rather than uninstall every logged artefact.
uninstall_only_rc=0
uninstall_only_out="$(
  HOME="$only_home" DEPLOYED_ARTIFACTS_LOG="$only_log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --uninstall --target claude \
    --only format_markdown 2>&1
)" || uninstall_only_rc=$?
[[ "$uninstall_only_rc" -ne 0 ]] ||
  fail "--uninstall with --only should abort, got: $uninstall_only_out"
printf '%s\n' "$uninstall_only_out" | grep -Fq -- 'cannot be combined with --uninstall' ||
  fail "--uninstall with --only should name both flags, got: $uninstall_only_out"
assert_file "$only_home/.claude/skills/language_humanizer/SKILL.md"
assert_file "$only_home/.claude/skills/format_markdown/SKILL.md"

# An unknown --only name aborts before any backup or copy. A name that --type
# filters out stays known, which is how tests/lib/micro_deploy.py calls it.
unknown_home="${SCRATCH}/only-unknown-home"
unknown_log="${SCRATCH}/only-unknown.log"
mkdir -p "$unknown_home"
unknown_rc=0
unknown_out="$(
  HOME="$unknown_home" DEPLOYED_ARTIFACTS_LOG="$unknown_log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --target claude \
    --only language_humanizer,no_such_artefact 2>&1
)" || unknown_rc=$?
[[ "$unknown_rc" -ne 0 ]] ||
  fail "--only with an unknown name should abort, got: $unknown_out"
printf '%s\n' "$unknown_out" | grep -Fq -- "Unknown artefact name 'no_such_artefact'" ||
  fail "--only should name the unknown artefact, got: $unknown_out"
[[ -z "$(ls -A "$unknown_home")" ]] ||
  fail "--only with an unknown name should write nothing, got: $(ls -A "$unknown_home")"
HOME="$unknown_home" DEPLOYED_ARTIFACTS_LOG="$unknown_log" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --target claude --type skill \
  --only language_humanizer,natural-language >/dev/null ||
  fail "--only should accept a name that --type filters out"
assert_file "$unknown_home/.claude/skills/language_humanizer/SKILL.md"

# An empty filter means "no filter" downstream, so an --only value that names
# nothing has to abort rather than deploy every artefact.
empty_home="${SCRATCH}/only-empty-home"
mkdir -p "$empty_home"
for empty_only in "" " , "; do
  empty_rc=0
  empty_out="$(
    HOME="$empty_home" DEPLOYED_ARTIFACTS_LOG="${SCRATCH}/only-empty.log" \
      "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --target claude \
      --only "$empty_only" 2>&1
  )" || empty_rc=$?
  [[ "$empty_rc" -ne 0 ]] ||
    fail "--only '$empty_only' should abort, got: $empty_out"
  printf '%s\n' "$empty_out" | grep -Fq -- '--only needs at least one artefact name' ||
    fail "--only '$empty_only' should say it needs a name, got: $empty_out"
done
[[ -z "$(ls -A "$empty_home")" ]] ||
  fail "--only with no name should write nothing, got: $(ls -A "$empty_home")"

# --only is a deploy filter, so a --clear-backups run with no scope stops with
# the missing-scope error rather than clearing backups and ignoring it. The
# control run without --only proves cleanup would remove the planted backup.
cleanup_only_home="${SCRATCH}/only-cleanup-home"
cleanup_only_backup="${cleanup_only_home}/.claude_20260101_000000"
mkdir -p "$cleanup_only_backup"
printf 'backup\n' > "$cleanup_only_backup/marker"
cleanup_only_rc=0
cleanup_only_out="$(
  HOME="$cleanup_only_home" DEPLOYED_ARTIFACTS_LOG="${SCRATCH}/only-cleanup.log" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --clear-backups --target claude \
    --only language_humanizer 2>&1
)" || cleanup_only_rc=$?
[[ "$cleanup_only_rc" -ne 0 ]] ||
  fail "--clear-backups with --only and no scope should abort, got: $cleanup_only_out"
printf '%s\n' "$cleanup_only_out" | grep -Fq -- 'requires an explicit scope' ||
  fail "--clear-backups with --only should name the missing scope, got: $cleanup_only_out"
assert_file "$cleanup_only_backup/marker"
HOME="$cleanup_only_home" DEPLOYED_ARTIFACTS_LOG="${SCRATCH}/only-cleanup.log" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --clear-backups --target claude >/dev/null ||
  fail "cleanup-only --clear-backups without --only should succeed"
[[ ! -e "$cleanup_only_backup" ]] ||
  fail "cleanup-only --clear-backups should remove the planted managed backup"

# ---------------------------------------------------------------------------
# Scoped --uninstall limits removal to the scope it names.
#
# The shared fixture deploys the language_humanizer skill for the claude
# target into the scratch home (global scope) and into two scratch projects,
# staged afresh before each consuming scenario, so every scenario observes the
# copies and log entries it asserts on. A dry run reports what it would remove
# on the would-rm, would-strip, and would-restore labels; an entry the run
# leaves unselected stays out of that listing and is reported on the skip
# label as "out-of-scope for this uninstall: <logged path>".
# ---------------------------------------------------------------------------
SCOPE_HOME="${SCRATCH}/scope-home"
SCOPE_P1="${SCRATCH}/scope-p1"
SCOPE_P2="${SCRATCH}/scope-p2"
SCOPE_LOG="${SCRATCH}/scope-deployed.log"
SCOPE_SKILL="language_humanizer"
SCOPE_HOME_DEST="${SCOPE_HOME}/.claude/skills/${SCOPE_SKILL}"
SCOPE_P1_DEST="${SCOPE_P1}/.claude/skills/${SCOPE_SKILL}"
SCOPE_P2_DEST="${SCOPE_P2}/.claude/skills/${SCOPE_SKILL}"
SCOPE_HOME_KEY="${SCOPE_HOME}/.claude/settings.json[outputStyle]"
SCOPE_P1_KEY="${SCOPE_P1}/.claude/settings.json[outputStyle]"
SCOPE_P2_KEY="${SCOPE_P2}/.claude/settings.json[outputStyle]"

scope_deploy() {
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" "$@" \
    --target claude --type skill --only "$SCOPE_SKILL" >/dev/null
}

scope_stage_all() {
  mkdir -p "$SCOPE_HOME" "$SCOPE_P1" "$SCOPE_P2"
  rm -f "$SCOPE_LOG"
  rm -rf "$SCOPE_HOME/.claude" "$SCOPE_P1/.claude" "$SCOPE_P2/.claude"
  scope_deploy --global
  scope_deploy --project-dir "$SCOPE_P1"
  scope_deploy --project-dir "$SCOPE_P2"
  assert_file "$SCOPE_HOME_DEST/SKILL.md"
  assert_file "$SCOPE_P1_DEST/SKILL.md"
  assert_file "$SCOPE_P2_DEST/SKILL.md"
}

scope_uninstall() {
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" "$@" \
    --target claude --type skill --uninstall
}

scope_uninstall_dry() {
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" "$@" \
    --target claude --type skill --uninstall --dry-run
}

assert_scope_reported() {
  local output="$1" path="$2"
  printf '%s\n' "$output" | grep -Fq "out-of-scope for this uninstall: $path" ||
    fail "expected out-of-scope report for $path, got: $output"
}

assert_unlisted() {
  local output="$1" path="$2"
  if printf '%s\n' "$output" | grep -E 'would-(rm|strip|restore)' | grep -Fq -- "$path"; then
    fail "expected $path to stay out of the removal listing, got: $output"
  fi
}

assert_log_has() {
  grep -Fq -- "$1" "$SCOPE_LOG" || fail "expected the deploy log to keep $1"
}

assert_log_lacks() {
  if grep -Fq -- "$1" "$SCOPE_LOG"; then
    fail "expected the deploy log to drop $1"
  fi
}

# --project-dir <first project> removes only that project.
scope_stage_all
scope_uninstall --project-dir "$SCOPE_P1" >/dev/null
[[ ! -e "$SCOPE_P1_DEST" ]] || fail "project uninstall should remove the first project's copy"
assert_file "$SCOPE_HOME_DEST/SKILL.md"
assert_file "$SCOPE_P2_DEST/SKILL.md"
assert_log_lacks "$SCOPE_P1_DEST"
assert_log_has "$SCOPE_HOME_DEST"
assert_log_has "$SCOPE_P2_DEST"

# --global removes only the global scope and reports the mismatched entry.
scope_stage_all
global_out="$(scope_uninstall --global)"
[[ ! -e "$SCOPE_HOME_DEST" ]] || fail "global uninstall should remove the global copy"
assert_file "$SCOPE_P1_DEST/SKILL.md"
assert_file "$SCOPE_P2_DEST/SKILL.md"
assert_log_lacks "$SCOPE_HOME_DEST"
assert_log_has "$SCOPE_P1_DEST"
assert_log_has "$SCOPE_P2_DEST"
assert_scope_reported "$global_out" "$SCOPE_P1_DEST"

# --project-dir dry run lists exactly the first project's copy.
scope_stage_all
p1_dry="$(scope_uninstall_dry --project-dir "$SCOPE_P1")"
[[ "$(printf '%s\n' "$p1_dry" | grep -c 'would-rm' || true)" -eq 1 ]] ||
  fail "project dry run should list exactly one would-rm, got: $p1_dry"
printf '%s\n' "$p1_dry" | grep 'would-rm' | grep -Fq -- "$SCOPE_P1_DEST" ||
  fail "project dry run should name the first project's copy, got: $p1_dry"
assert_unlisted "$p1_dry" "$SCOPE_HOME_DEST"
assert_unlisted "$p1_dry" "$SCOPE_P2_DEST"

# --global dry run lists exactly the global copy.
scope_stage_all
global_dry="$(scope_uninstall_dry --global)"
[[ "$(printf '%s\n' "$global_dry" | grep -c 'would-rm' || true)" -eq 1 ]] ||
  fail "global dry run should list exactly one would-rm, got: $global_dry"
printf '%s\n' "$global_dry" | grep 'would-rm' | grep -Fq -- "$SCOPE_HOME_DEST" ||
  fail "global dry run should name the global copy, got: $global_dry"
assert_unlisted "$global_dry" "$SCOPE_P1_DEST"
assert_unlisted "$global_dry" "$SCOPE_P2_DEST"

# Its own fixture: a four-field style path[key] entry for the global settings
# file and for each project's settings file.
scope_stage_settings() {
  mkdir -p "$SCOPE_HOME/.claude" "$SCOPE_P1/.claude" "$SCOPE_P2/.claude"
  rm -f "$SCOPE_LOG"
  printf '%s\n' '{"outputStyle":"home-prior"}' > "$SCOPE_HOME/.claude/settings.json"
  printf '%s\n' '{"outputStyle":"p1-prior"}' > "$SCOPE_P1/.claude/settings.json"
  printf '%s\n' '{"outputStyle":"p2-prior"}' > "$SCOPE_P2/.claude/settings.json"
}

scope_stage_settings
{
  printf '%s\t%s\t%s\t%s\n' "$SCOPE_HOME_KEY" claude style styles/natural-language.md
  printf '%s\t%s\t%s\t%s\n' "$SCOPE_P1_KEY" claude style styles/natural-language.md
  printf '%s\t%s\t%s\t%s\n' "$SCOPE_P2_KEY" claude style styles/natural-language.md
} >> "$SCOPE_LOG"
style_dry="$(
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$SCOPE_P1" \
    --target claude --type style --uninstall --dry-run
)"
[[ "$(printf '%s\n' "$style_dry" | grep -c 'would-strip' || true)" -eq 1 ]] ||
  fail "four-field style dry run should list exactly one would-strip, got: $style_dry"
printf '%s\n' "$style_dry" | grep 'would-strip' | grep -Fq -- "$SCOPE_P1_KEY" ||
  fail "four-field style dry run should name the first project's key, got: $style_dry"
assert_unlisted "$style_dry" "$SCOPE_HOME_KEY"
assert_unlisted "$style_dry" "$SCOPE_P2_KEY"
assert_log_has "$SCOPE_HOME_KEY"
assert_log_has "$SCOPE_P2_KEY"

# Its own fixture: two five-field style path[key] entries, one per scope.
scope_stage_settings
{
  printf '%s\t%s\t%s\t%s\t%s\n' "$SCOPE_HOME_KEY" claude style styles/natural-language.md '"home-prior"'
  printf '%s\t%s\t%s\t%s\t%s\n' "$SCOPE_P1_KEY" claude style styles/natural-language.md '"p1-prior"'
} >> "$SCOPE_LOG"
restore_dry="$(
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$SCOPE_P1" \
    --target claude --type style --uninstall --dry-run
)"
[[ "$(printf '%s\n' "$restore_dry" | grep -c 'would-restore' || true)" -eq 1 ]] ||
  fail "five-field style dry run should list exactly one would-restore, got: $restore_dry"
printf '%s\n' "$restore_dry" | grep 'would-restore' | grep -Fq -- "$SCOPE_P1_KEY" ||
  fail "five-field style dry run should name the first project's key, got: $restore_dry"
assert_unlisted "$restore_dry" "$SCOPE_HOME_KEY"

# Same five-field fixture, real run: the first project's entry leaves the log
# and the global line survives verbatim with its prior.
scope_stage_settings
{
  printf '%s\t%s\t%s\t%s\t%s\n' "$SCOPE_HOME_KEY" claude style styles/natural-language.md '"home-prior"'
  printf '%s\t%s\t%s\t%s\t%s\n' "$SCOPE_P1_KEY" claude style styles/natural-language.md '"p1-prior"'
} >> "$SCOPE_LOG"
HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --project-dir "$SCOPE_P1" \
  --target claude --type style --uninstall >/dev/null
assert_log_lacks "$SCOPE_P1_KEY"
global_line="$(printf '%s\t%s\t%s\t%s\t%s' "$SCOPE_HOME_KEY" claude style styles/natural-language.md '"home-prior"')"
grep -Fxq -- "$global_line" "$SCOPE_LOG" ||
  fail "the unselected global five-field line must survive verbatim"

# A scopeless --uninstall still reaches every scope.
scope_stage_all
scope_uninstall >/dev/null
[[ ! -e "$SCOPE_HOME_DEST" ]] || fail "scopeless uninstall should remove the global copy"
[[ ! -e "$SCOPE_P1_DEST" ]] || fail "scopeless uninstall should remove the first project's copy"
[[ ! -e "$SCOPE_P2_DEST" ]] || fail "scopeless uninstall should remove the second project's copy"
assert_log_lacks "$SCOPE_HOME_DEST"
assert_log_lacks "$SCOPE_P1_DEST"
assert_log_lacks "$SCOPE_P2_DEST"

# A neither-form entry under --global is reported and kept.
SCOPE_NEITHER="${SCRATCH}/scope-neither/outside/${SCOPE_SKILL}"
mkdir -p "$SCOPE_NEITHER"
rm -f "$SCOPE_LOG"
printf '%s\t%s\t%s\t%s\n' "$SCOPE_NEITHER" claude skill styles/natural-language.md > "$SCOPE_LOG"
neither_global_out="$(scope_uninstall --global)"
assert_scope_reported "$neither_global_out" "$SCOPE_NEITHER"
[[ -e "$SCOPE_NEITHER" ]] || fail "a neither-form path should stay in place under --global uninstall"
assert_log_has "$SCOPE_NEITHER"

# A retired-target, neither-form entry under --global with no --target filter
# prints its stale line and the scope report, and stays.
SCOPE_RETIRED="${SCRATCH}/scope-neither/retired/${SCOPE_SKILL}"
mkdir -p "$SCOPE_RETIRED"
rm -f "$SCOPE_LOG"
printf '%s\t%s\t%s\t%s\n' "$SCOPE_RETIRED" retiredtool skill styles/natural-language.md > "$SCOPE_LOG"
retired_global_out="$(
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --global --type skill --uninstall
)"
printf '%s\n' "$retired_global_out" | grep -Fq "targets removed app 'retiredtool'" ||
  fail "retired-target global run should print the stale line, got: $retired_global_out"
assert_scope_reported "$retired_global_out" "$SCOPE_RETIRED"
[[ -e "$SCOPE_RETIRED" ]] || fail "a retired-target neither-form path should stay under --global"
assert_log_has "$SCOPE_RETIRED"

# A scopeless --uninstall still removes that retired-target entry.
rm -f "$SCOPE_LOG"
printf '%s\t%s\t%s\t%s\n' "$SCOPE_RETIRED" retiredtool skill styles/natural-language.md > "$SCOPE_LOG"
retired_dry="$(
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --type skill --uninstall --dry-run
)"
printf '%s\n' "$retired_dry" | grep -E 'would-(rm|strip|restore)' | grep -Fq -- "$SCOPE_RETIRED" ||
  fail "scopeless dry run should list the retired-target entry, got: $retired_dry"
HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --type skill --uninstall >/dev/null
[[ ! -e "$SCOPE_RETIRED" ]] || fail "scopeless uninstall should remove the retired-target path"
assert_log_lacks "$SCOPE_RETIRED"

# A neither-form entry under --project-dir is reported and kept.
mkdir -p "$SCOPE_NEITHER"
rm -f "$SCOPE_LOG"
printf '%s\t%s\t%s\t%s\n' "$SCOPE_NEITHER" claude skill styles/natural-language.md > "$SCOPE_LOG"
neither_project_out="$(scope_uninstall --project-dir "$SCOPE_P1")"
assert_scope_reported "$neither_project_out" "$SCOPE_NEITHER"
[[ -e "$SCOPE_NEITHER" ]] || fail "a neither-form path should stay in place under --project-dir uninstall"
assert_log_has "$SCOPE_NEITHER"

# Under --project-dir the global copy and the second project's copy are each
# reported and kept.
scope_stage_all
project_out="$(scope_uninstall --project-dir "$SCOPE_P1")"
assert_scope_reported "$project_out" "$SCOPE_HOME_DEST"
assert_scope_reported "$project_out" "$SCOPE_P2_DEST"
assert_file "$SCOPE_HOME_DEST/SKILL.md"
assert_file "$SCOPE_P2_DEST/SKILL.md"
assert_log_has "$SCOPE_HOME_DEST"
assert_log_has "$SCOPE_P2_DEST"

# A scopeless --uninstall still removes a neither-form entry for a live target.
mkdir -p "$SCOPE_NEITHER"
rm -f "$SCOPE_LOG"
printf '%s\t%s\t%s\t%s\n' "$SCOPE_NEITHER" claude skill styles/natural-language.md > "$SCOPE_LOG"
live_dry="$(
  HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
    "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --target claude --type skill --uninstall --dry-run
)"
printf '%s\n' "$live_dry" | grep -E 'would-(rm|strip|restore)' | grep -Fq -- "$SCOPE_NEITHER" ||
  fail "scopeless dry run should list the neither-form entry, got: $live_dry"
HOME="$SCOPE_HOME" DEPLOYED_ARTIFACTS_LOG="$SCOPE_LOG" \
  "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --target claude --type skill --uninstall >/dev/null
[[ ! -e "$SCOPE_NEITHER" ]] || fail "scopeless uninstall should remove the neither-form path"
assert_log_lacks "$SCOPE_NEITHER"

# ---------------------------------------------------------------------------
# logged_path_scope derives a logged entry's scope from its deployed path and
# target id, through the style_run.sh sourcing pattern (argv + scratch HOME).
# ---------------------------------------------------------------------------
SCOPE_HELPER_LOG="${SCRATCH}/scope-helper.log"

scope_helper_result() {  # path target argv...
  local path="$1" target_id="$2"
  shift 2
  (
    # shellcheck disable=SC2034
    DEPLOYMENT_SH_SKIP_MAIN=1
    # shellcheck disable=SC2034
    HOME="$SCOPE_HOME"
    # shellcheck disable=SC2034
    DEPLOYED_ARTIFACTS_LOG="$SCOPE_HELPER_LOG"
    # shellcheck source=/dev/null
    source "$DEPLOY_SCRIPT"
    local value rc
    value="$(logged_path_scope "$path" "$target_id")"
    rc=$?
    printf '%s\t%s' "$rc" "$value"
  )
}

scope_helper_assert() {  # label want path target argv...
  local label="$1" want="$2" path="$3" target_id="$4"
  shift 4
  local rc value
  IFS=$'\t' read -r rc value <<< "$(scope_helper_result "$path" "$target_id" "$@")" || true
  [[ "$rc" == "0" ]] || fail "logged_path_scope [$label] returned status $rc"
  [[ "$value" == "$want" ]] || fail "logged_path_scope [$label]: got '$value' want '$want'"
}

mkdir -p "$SCOPE_HOME/.claude" "$SCOPE_P1/.claude" "$SCOPE_P2/.claude"

SCOPE_VSCODE_PROMPTS="$SCOPE_HOME/Library/Application Support/Code/User/prompts"
case "$OSTYPE" in
  darwin*) ;;
  *) SCOPE_VSCODE_PROMPTS="$SCOPE_HOME/.config/Code/User/prompts" ;;
esac
SCOPE_VSCODE_SETTINGS_DIR="${SCOPE_VSCODE_PROMPTS%/*}"

# Project form: every project-relative suffix the # Target directories block
# appends for each target.
scope_helper_assert "claude project root" "$SCOPE_P1" "$SCOPE_P1/.claude/skills/$SCOPE_SKILL" claude --project-dir "$SCOPE_P1"
scope_helper_assert "claude second project" "$SCOPE_P2" "$SCOPE_P2/.claude/skills/$SCOPE_SKILL" claude --project-dir "$SCOPE_P1"
scope_helper_assert "cursor project" "$SCOPE_P1" "$SCOPE_P1/.cursor/rules/x" cursor --project-dir "$SCOPE_P1"
scope_helper_assert "codex project .codex" "$SCOPE_P1" "$SCOPE_P1/.codex/x" codex --project-dir "$SCOPE_P1"
scope_helper_assert "codex project agents skills" "$SCOPE_P1" "$SCOPE_P1/.agents/skills/x" codex --project-dir "$SCOPE_P1"
scope_helper_assert "antigravity project" "$SCOPE_P1" "$SCOPE_P1/.agents/skills/x" antigravity --project-dir "$SCOPE_P1"
scope_helper_assert "opencode project" "$SCOPE_P1" "$SCOPE_P1/.opencode/x" opencode --project-dir "$SCOPE_P1"
scope_helper_assert "vscode project github" "$SCOPE_P1" "$SCOPE_P1/.github/x" vscode --project-dir "$SCOPE_P1"
scope_helper_assert "vscode project prompts" "$SCOPE_P1" "$SCOPE_P1/.github/prompts/x" vscode --project-dir "$SCOPE_P1"

# Global form: every global-form root per target.
scope_helper_assert "claude global root" global "$SCOPE_HOME/.claude/skills/$SCOPE_SKILL" claude --project-dir "$SCOPE_P1"
scope_helper_assert "cursor global root" global "$SCOPE_HOME/.cursor/x" cursor --project-dir "$SCOPE_P1"
scope_helper_assert "codex global root" global "$SCOPE_HOME/.codex/x" codex --project-dir "$SCOPE_P1"
scope_helper_assert "antigravity global root" global "$SCOPE_HOME/.gemini/x" antigravity --project-dir "$SCOPE_P1"
scope_helper_assert "opencode global root" global "$SCOPE_HOME/.config/opencode/x" opencode --project-dir "$SCOPE_P1"
scope_helper_assert "vscode copilot root" global "$SCOPE_HOME/.copilot/x" vscode --project-dir "$SCOPE_P1"
scope_helper_assert "vscode prompts root" global "$SCOPE_VSCODE_PROMPTS/x" vscode --project-dir "$SCOPE_P1"
scope_helper_assert "vscode settings key" global "$SCOPE_VSCODE_SETTINGS_DIR/settings.json[outputStyle]" vscode --project-dir "$SCOPE_P1"

# Neither form, and an unknown target id, derive the empty string.
scope_helper_assert "claude neither form" "" "${SCRATCH}/scope-helper/elsewhere/$SCOPE_SKILL" claude --project-dir "$SCOPE_P1"
scope_helper_assert "unknown target" "" "$SCOPE_HOME/.claude/x" retiredtool --project-dir "$SCOPE_P1"

# The helper ignores the scope flags: --global argv derives the same scopes.
scope_helper_assert "global argv first project" "$SCOPE_P1" "$SCOPE_P1/.claude/skills/$SCOPE_SKILL" claude --global
scope_helper_assert "global argv global root" global "$SCOPE_HOME/.claude/skills/$SCOPE_SKILL" claude --global

# A path equal to a root, a suffixed path, the HOME-sibling beside a root, and
# --project-dir "$HOME" (which fits both forms, so the global test wins).
scope_helper_assert "claude root equal" global "$SCOPE_HOME/.claude" claude --project-dir "$SCOPE_P1"
scope_helper_assert "claude root key" global "$SCOPE_HOME/.claude/settings.json[outputStyle]" claude --project-dir "$SCOPE_P1"
scope_helper_assert "project root equal" "$SCOPE_P1" "$SCOPE_P1/.claude" claude --project-dir "$SCOPE_P1"
scope_helper_assert "project root key" "$SCOPE_P1" "$SCOPE_P1/.claude/settings.json[outputStyle]" claude --project-dir "$SCOPE_P1"
scope_helper_assert "home sibling beside root" "" "$SCOPE_HOME/.claudex/x" claude --project-dir "$SCOPE_P1"
scope_helper_assert "HOME as project dir" global "$SCOPE_HOME/.claude" claude --project-dir "$SCOPE_HOME"

# A project directory that itself ends in the suffix recovers at that
# directory, not one level above it.
scope_helper_assert "repeated suffix" "$SCOPE_P1/.claude" \
  "$SCOPE_P1/.claude/.claude/skills/$SCOPE_SKILL" claude --project-dir "$SCOPE_P1/.claude"

printf 'OpenCode deployment regression passed\n'
printf 'Antigravity deployment regression passed\n'
printf 'Python bytecode exclusion regression passed\n'
printf 'Backup skip of sockets and FIFOs regression passed\n'
printf 'Backup vanished-file rsync exit handling regression passed\n'
printf 'Startup gate for jq, perl, and rsync regression passed\n'
printf 'Cleanup-only --clear-backups skips the jq, perl, and rsync startup gate\n'
printf 'DEPLOYED_ARTIFACTS_LOG override and --only regression passed\n'
printf 'Unknown --only name and --only with --uninstall abort regression passed\n'
printf 'Empty --only value abort regression passed\n'
printf 'Cleanup-only --clear-backups with --only stops for a missing scope regression passed\n'
printf 'Scoped --uninstall limits removal to the scope it names regression passed\n'
printf 'logged_path_scope derives a logged entry scope regression passed\n'
