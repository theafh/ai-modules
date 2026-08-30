#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HOOK="${REPO_ROOT}/plugins/ai_dev/hooks/charter_guardrail.sh"
DEPLOY="${REPO_ROOT}/deployment/deployment.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# doc_has PATTERN FILE...  -> exit 0 if the ERE PATTERN matches in any FILE.
# Prefer ripgrep; fall back to grep -E when rg is absent. Inside Claude Code
# `rg` is a shell function that a bare `bash` subshell does not inherit, so the
# fallback keeps these doc-content assertions runnable from any shell.
doc_has() {
  local pattern=$1
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$@"
  else
    grep -qE "$pattern" "$@"
  fi
}

run_hook() {
  local input_json=$1
  local out_file="${TMP_ROOT}/hook.out"
  local err_file="${TMP_ROOT}/hook.err"

  set +e
  printf '%s' "$input_json" | "$HOOK" >"$out_file" 2>"$err_file"
  HOOK_RC=$?
  set -e

  HOOK_ERR="$(cat "$err_file")"
  HOOK_OUT="$(cat "$out_file")"
}

create_git_fixture() {
  local fixture=$1
  mkdir -p "$fixture"
  git -C "$fixture" init -q
  git -C "$fixture" checkout -q -b main
  git -C "$fixture" config user.email "tests@example.invalid"
  git -C "$fixture" config user.name "Test Runner"
}

# Shell-tool hook input. Both Claude and Codex report the shell tool as
# tool_name "Bash" and carry the command at tool_input.command.
bash_json() {
  jq -n --arg cwd "$1" --arg command "$2" \
    '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}'
}

antigravity_json() {
  jq -n --arg cwd "$1" --arg tool "$2" --arg command "$3" \
    '{toolCall: {name: $tool, args: {CommandLine: $command, Cwd: $cwd}}, workspacePaths: [$cwd]}'
}

# expect_block DESC JSON -> the hook must deny (rc 2) and name the branch gate.
expect_block() {
  run_hook "$2"
  [[ "$HOOK_RC" -eq 2 ]] ||
    fail "$1: expected block (rc 2), got rc=$HOOK_RC (stderr: $HOOK_ERR)"
  grep -q 'guardrail/charter-\*' <<< "$HOOK_ERR" ||
    fail "$1: block reason should name the guardrail branch pattern"
}

# expect_pass DESC JSON -> the hook must allow (rc 0).
expect_pass() {
  run_hook "$2"
  [[ "$HOOK_RC" -eq 0 ]] ||
    fail "$1: expected pass (rc 0), got rc=$HOOK_RC (stderr: $HOOK_ERR)"
}

expect_antigravity_block() {
  run_hook "$2"
  [[ "$HOOK_RC" -eq 0 ]] ||
    fail "$1: expected Antigravity block at rc 0, got rc=$HOOK_RC (stderr: $HOOK_ERR stdout: $HOOK_OUT)"
  jq -e '.decision == "deny" and (.reason | length > 0)' <<< "$HOOK_OUT" >/dev/null ||
    fail "$1: expected Antigravity deny decision with reason, got stdout: $HOOK_OUT"
}

expect_antigravity_pass() {
  run_hook "$2"
  [[ "$HOOK_RC" -eq 0 ]] ||
    fail "$1: expected Antigravity pass (rc 0), got rc=$HOOK_RC (stderr: $HOOK_ERR stdout: $HOOK_OUT)"
  [[ -z "$HOOK_OUT" ]] ||
    fail "$1: expected no Antigravity deny decision, got stdout: $HOOK_OUT"
}

charter_repo="${TMP_ROOT}/charter repo"
create_git_fixture "$charter_repo"
printf '# Fixture Charter\n' > "${charter_repo}/CHARTER.md"
git -C "$charter_repo" add CHARTER.md
git -C "$charter_repo" commit -q -m "add charter"

# A scratch PATH provides every tool the script needs except jq for jq-missing
# scenarios. It must exist before the Antigravity envelope checks use it.
nojq_bin="${TMP_ROOT}/nojq-bin"
mkdir -p "$nojq_bin"
for tool in cat git mktemp dirname basename sed grep; do
  ln -sf "$(command -v "$tool")" "${nojq_bin}/${tool}"
done

claude_json="$(jq -n \
  --arg cwd "$charter_repo" \
  --arg path "${charter_repo}/CHARTER.md" \
  '{cwd: $cwd, tool_name: "Edit", tool_input: {file_path: $path}}')"
run_hook "$claude_json"
[[ "$HOOK_RC" -eq 2 ]] || fail "Claude-shaped CHARTER.md edit should block on main, got rc=$HOOK_RC"
grep -q 'guardrail/charter-\*' <<< "$HOOK_ERR" ||
  fail "Claude-shaped block reason should name the guardrail branch pattern"

codex_patch=$'*** Begin Patch\n*** Update File: CHARTER.md\n@@\n-old\n+new\n*** End Patch\n'
codex_json="$(jq -n \
  --arg cwd "$charter_repo" \
  --arg command "$codex_patch" \
  '{cwd: $cwd, tool_name: "apply_patch", tool_input: {command: $command}}')"
run_hook "$codex_json"
[[ "$HOOK_RC" -eq 2 ]] || fail "Codex-shaped CHARTER.md patch should block on main, got rc=$HOOK_RC"
grep -q 'guardrail/charter-\*' <<< "$HOOK_ERR" ||
  fail "Codex-shaped block reason should name the guardrail branch pattern"

non_charter_json="$(jq -n \
  --arg cwd "$charter_repo" \
  --arg path "${charter_repo}/README.md" \
  '{cwd: $cwd, tool_name: "Edit", tool_input: {file_path: $path}}')"
run_hook "$non_charter_json"
[[ "$HOOK_RC" -eq 0 ]] || fail "Non-charter edit should pass when CHARTER.md exists, got rc=$HOOK_RC"

# --- Shell-tool bypass coverage (on main) -----------------------------------
# A charter mutation through the Bash tool must be blocked no matter which shell
# idiom carries it: redirection, here-doc, in-place editor, file mover, or a
# ref restore. These are the paths that never hit the Edit|Write / apply_patch
# matchers and so previously slipped the gate.
expect_block "redirect overwrite"           "$(bash_json "$charter_repo" 'echo drift > CHARTER.md')"
expect_block "redirect overwrite (glued)"   "$(bash_json "$charter_repo" 'echo drift >CHARTER.md')"
expect_block "redirect append"              "$(bash_json "$charter_repo" "printf 'x\\n' >> CHARTER.md")"
expect_block "dot-slash redirect"           "$(bash_json "$charter_repo" 'echo x > ./CHARTER.md')"
expect_block "quoted redirect target"       "$(bash_json "$charter_repo" 'echo x > "CHARTER.md"')"
expect_block "here-doc redirect"            "$(bash_json "$charter_repo" "cat > CHARTER.md <<'EOF'
drift
EOF")"
expect_block "sed in place"                 "$(bash_json "$charter_repo" "sed -i 's/Charter/Drift/' CHARTER.md")"
expect_block "sed in place with backup"     "$(bash_json "$charter_repo" "sed -i.bak 's/a/b/' CHARTER.md")"
expect_block "sed combined flags"           "$(bash_json "$charter_repo" "sed -ri 's/a/b/' CHARTER.md")"
expect_block "perl in place"                "$(bash_json "$charter_repo" "perl -i -pe 's/a/b/' CHARTER.md")"
expect_block "tee overwrite"                "$(bash_json "$charter_repo" 'echo x | tee CHARTER.md')"
expect_block "mv onto charter"              "$(bash_json "$charter_repo" 'mv /tmp/new.md CHARTER.md')"
expect_block "mv charter away (rename)"     "$(bash_json "$charter_repo" 'mv CHARTER.md CHARTER.old')"
expect_block "cp onto charter"              "$(bash_json "$charter_repo" 'cp other.md CHARTER.md')"
expect_block "rm charter"                   "$(bash_json "$charter_repo" 'rm -f CHARTER.md')"
expect_block "git checkout ref -- charter"  "$(bash_json "$charter_repo" 'git checkout main -- CHARTER.md')"
expect_block "git restore charter"          "$(bash_json "$charter_repo" 'git restore --source=main -- CHARTER.md')"
expect_block "mutation after a read chain"  "$(bash_json "$charter_repo" 'cat README.md && sed -i s/a/b/ CHARTER.md')"

# --- Read-only and non-charter shell commands must never block --------------
# The every-session consumption model reads CHARTER.md constantly; blocking a
# read would break it. A subdir CHARTER.md is not the protected root contract.
mkdir -p "${charter_repo}/docs"
expect_pass "cat charter (read)"            "$(bash_json "$charter_repo" 'cat CHARTER.md')"
expect_pass "grep charter (read)"           "$(bash_json "$charter_repo" 'grep -n Charter CHARTER.md')"
expect_pass "test -f charter (read)"        "$(bash_json "$charter_repo" 'test -f CHARTER.md && echo yes')"
expect_pass "sed print charter (no -i)"     "$(bash_json "$charter_repo" "sed -n '1,3p' CHARTER.md")"
expect_pass "git show charter (read)"       "$(bash_json "$charter_repo" 'git show HEAD:CHARTER.md')"
expect_pass "git log charter (read)"        "$(bash_json "$charter_repo" 'git log --oneline -- CHARTER.md')"
expect_pass "git diff charter (read)"       "$(bash_json "$charter_repo" 'git diff -- CHARTER.md')"
expect_pass "redirect to non-charter"       "$(bash_json "$charter_repo" 'echo x > README.md')"
expect_pass "sed -i on non-charter"         "$(bash_json "$charter_repo" "sed -i 's/a/b/' README.md")"
expect_pass "mutate a subdir CHARTER.md"    "$(bash_json "$charter_repo" 'echo x > docs/CHARTER.md')"

# --- Antigravity envelope coverage (on main) --------------------------------
expect_antigravity_block "antigravity run_command write" \
  "$(antigravity_json "$charter_repo" run_command 'echo x > CHARTER.md')"
expect_antigravity_pass "antigravity run_command read" \
  "$(antigravity_json "$charter_repo" run_command 'cat CHARTER.md')"

ag_write_json="$(jq -n --arg cwd "$charter_repo" --arg path "${charter_repo}/CHARTER.md" \
  '{toolCall: {name: "write_to_file", args: {AnyKey: $path, Cwd: $cwd}}, workspacePaths: [$cwd]}')"
expect_antigravity_block "antigravity write_to_file arbitrary key" "$ag_write_json"

ag_view_json="$(jq -n --arg cwd "$charter_repo" --arg path "${charter_repo}/CHARTER.md" \
  '{toolCall: {name: "view_file", args: {AbsolutePath: $path, Cwd: $cwd}}, workspacePaths: [$cwd]}')"
expect_antigravity_pass "antigravity view_file charter read" "$ag_view_json"

ag_grep_json="$(jq -n --arg cwd "$charter_repo" --arg path "${charter_repo}/CHARTER.md" \
  '{toolCall: {name: "grep_search", args: {Pattern: "CHARTER.md", Path: $path, Cwd: $cwd}}, workspacePaths: [$cwd]}')"
expect_antigravity_pass "antigravity grep_search charter read" "$ag_grep_json"

ag_find_json="$(jq -n --arg cwd "$charter_repo" \
  '{toolCall: {name: "find_by_name", args: {Pattern: "CHARTER.md", Cwd: $cwd}}, workspacePaths: [$cwd]}')"
expect_antigravity_block "antigravity unclassified find_by_name fails closed" "$ag_find_json"

outside_dir="${TMP_ROOT}/outside"
mkdir -p "$outside_dir"
ag_workspace_json="$(jq -n --arg root "$charter_repo" \
  '{toolCall: {name: "write_to_file", args: {TargetFile: "CHARTER.md"}}, workspacePaths: [$root]}')"
(
  cd "$outside_dir"
  expect_antigravity_block "antigravity workspacePaths fallback" "$ag_workspace_json"
)

malformed_ag_json="{\"toolCall\":{\"name\":\"write_to_file\",\"args\":{\"TargetFile\":\"${charter_repo}/CHARTER.md\""
set +e
printf '%s' "$malformed_ag_json" | "$HOOK" >"${TMP_ROOT}/malformed.out" 2>"${TMP_ROOT}/malformed.err"
malformed_rc=$?
set -e
[[ "$malformed_rc" -eq 2 ]] || fail "Malformed Antigravity envelope should exit 2, got rc=$malformed_rc"
grep -q 'not valid JSON' "${TMP_ROOT}/malformed.err" || fail "Malformed JSON stderr should explain the parse failure"
jq -e '.decision == "deny" and (.reason | test("not valid JSON"))' "${TMP_ROOT}/malformed.out" >/dev/null ||
  fail "Malformed JSON stdout should carry an Antigravity deny decision"

set +e
nojq_ag_out="$(printf '%s' "$ag_write_json" | env -i PATH="$nojq_bin" /bin/sh "$HOOK" 2>"${TMP_ROOT}/nojq-ag.err")"
nojq_ag_rc=$?
set -e
[[ "$nojq_ag_rc" -eq 2 ]] || fail "Antigravity jq-missing scenario should exit 2, got rc=$nojq_ag_rc"
grep -q 'jq is required' "${TMP_ROOT}/nojq-ag.err" || fail "Antigravity jq-missing stderr should name jq"
jq -e '.decision == "deny" and (.reason | test("jq is required"))' <<< "$nojq_ag_out" >/dev/null ||
  fail "Antigravity jq-missing stdout should carry a deny decision"

claude_marker_json="$(bash_json "$charter_repo" "printf 'the toolCall envelope\n' >> CHARTER.md")"
run_hook "$claude_marker_json"
[[ "$HOOK_RC" -eq 2 ]] || fail "Claude-shaped payload mentioning toolCall should still block by rc 2, got rc=$HOOK_RC"
grep -q 'guardrail/charter-\*' <<< "$HOOK_ERR" || fail "Claude marker block reason should name the guardrail branch"
[[ -z "$HOOK_OUT" ]] || fail "Claude-shaped marker payload should not emit an Antigravity decision"

expect_antigravity_block "antigravity structural toolCall selection" \
  "$(antigravity_json "$charter_repo" run_command "printf 'the toolCall envelope\n' >> CHARTER.md")"

printf 'Antigravity envelope scenarios passed\n'

git -C "$charter_repo" checkout -q -b guardrail/charter-test
run_hook "$claude_json"
[[ "$HOOK_RC" -eq 0 ]] || fail "Claude-shaped CHARTER.md edit should pass on guardrail branch, got rc=$HOOK_RC"
run_hook "$codex_json"
[[ "$HOOK_RC" -eq 0 ]] || fail "Codex-shaped CHARTER.md patch should pass on guardrail branch, got rc=$HOOK_RC"

# The same shell mutations are the reviewed path on a guardrail/charter-* branch.
expect_pass "guardrail: sed -i charter"     "$(bash_json "$charter_repo" "sed -i 's/a/b/' CHARTER.md")"
expect_pass "guardrail: redirect charter"   "$(bash_json "$charter_repo" 'echo x > CHARTER.md')"
expect_pass "guardrail: rm charter"         "$(bash_json "$charter_repo" 'rm -f CHARTER.md')"
expect_pass "guardrail: git checkout charter" "$(bash_json "$charter_repo" 'git checkout main -- CHARTER.md')"

no_charter_repo="${TMP_ROOT}/no charter repo"
create_git_fixture "$no_charter_repo"
printf '# Fixture Readme\n' > "${no_charter_repo}/README.md"
git -C "$no_charter_repo" add README.md
git -C "$no_charter_repo" commit -q -m "add readme"

no_charter_json="$(jq -n \
  --arg cwd "$no_charter_repo" \
  --arg path "${no_charter_repo}/CHARTER.md" \
  '{cwd: $cwd, tool_name: "Write", tool_input: {file_path: $path}}')"
run_hook "$no_charter_json"
[[ "$HOOK_RC" -eq 0 ]] || fail "Hook should stay inert when no CHARTER.md exists, got rc=$HOOK_RC"

# A shell command that names CHARTER.md in a repo that has none stays inert.
expect_pass "shell charter mention, no charter file" \
  "$(bash_json "$no_charter_repo" 'echo x > CHARTER.md')"

# hook_registers <hooks-json> <tool> <command-substring> — assert some matcher
# group in the file covers <tool> and runs a handler whose command contains
# <command-substring>. The matcher is treated as the regex the harness reads it
# as, so a group may be one tool ("Bash"), an alternation ("Edit|Write"), or an
# anchored set ("^(apply_patch|Bash)$"). Pinning matcher strings by equality is
# what rotted here: harness_portability's <codex_hook_schema> sanctions both one
# combined group and separate groups, so the shape is the author's call and only
# the coverage is the contract.
hook_registers() {
  jq -e --arg tool "$2" --arg cmd "$3" \
    '.hooks.PreToolUse[]
       | select(.matcher as $m | $tool | test($m))
       | .hooks[] | select(.command | contains($cmd))' \
    "$1" >/dev/null
}

CLAUDE_HOOKS="${REPO_ROOT}/plugins/ai_dev/hooks/hooks.json"
CODEX_PLUGIN_HOOKS="${REPO_ROOT}/plugins/ai_dev/hooks/codex-plugin-hooks.json"
CODEX_DEPLOY_HOOKS="${REPO_ROOT}/plugins/ai_dev/hooks/codex-custom-deploy-hooks.json"

# The harness resolves these at hook time, so the shell must pass them through
# unexpanded — the literal text is what has to appear in the JSON.
# shellcheck disable=SC2016
CLAUDE_ROOT_CMD='${CLAUDE_PLUGIN_ROOT}/hooks/charter_guardrail.sh'
# shellcheck disable=SC2016
PLUGIN_ROOT_CMD='${PLUGIN_ROOT}/hooks/charter_guardrail.sh'

# Claude plugin surface: file-writing tools plus the shell, since the hook fences
# shell-command edits of the charter too.
for tool in Edit Write Bash; do
  hook_registers "$CLAUDE_HOOKS" "$tool" "$CLAUDE_ROOT_CMD" ||
    fail "Claude plugin hooks.json should register charter_guardrail.sh for $tool"
done
hook_registers "$CLAUDE_HOOKS" apply_patch "$CLAUDE_ROOT_CMD" ||
  fail "Shared plugin hooks.json should also register the Codex apply_patch matcher"

# Codex plugin surface: the file the Codex manifest points at, resolving the
# script through ${PLUGIN_ROOT}. This is the layer that actually runs inside
# Codex, so it carries both the patch and the shell tool.
for tool in apply_patch Bash; do
  hook_registers "$CODEX_PLUGIN_HOOKS" "$tool" "$PLUGIN_ROOT_CMD" ||
    fail "Codex plugin hooks config should register charter_guardrail.sh for $tool"
done

# Codex config-layer deploy source: plugin-relative ./hooks/ command that
# deployment.sh rewrites to the deployed absolute path.
for tool in apply_patch Bash; do
  hook_registers "$CODEX_DEPLOY_HOOKS" "$tool" './hooks/charter_guardrail.sh' ||
    fail "Codex deploy-source hooks config should use ./hooks/charter_guardrail.sh for $tool"
done

jq -e '.hooks == "./hooks/codex-plugin-hooks.json"' \
  "${REPO_ROOT}/plugins/ai_dev/.codex-plugin/plugin.json" >/dev/null ||
  fail "Codex plugin manifest should point at ./hooks/codex-plugin-hooks.json"

# No repo-local Codex hook activation. A committed <repo>/.codex/hooks.json is an
# additive layer on top of the installed plugin hook, so the guardrail would run
# twice in this repo; harness_portability's <codex_project_hooks> keeps project
# hooks out of a plugin source repo for exactly that reason.
if [[ -e "${REPO_ROOT}/.codex/hooks.json" ]]; then
  fail "Repo should carry no .codex/hooks.json — it duplicates the plugin hook layer"
fi

if doc_has 'dormant until openai/codex#16430|plugin-declared hook installs but does not run|fires hooks only from config-layer files' \
  "${REPO_ROOT}/tasks/archive/task-family_charter-guardrail-for-autonomy.md" \
  "${REPO_ROOT}/plugins/ai_dev/skills/harness_portability/SKILL.md" \
  "${REPO_ROOT}/plugins/ai_dev/README.md" \
  "${REPO_ROOT}/README.md"; then
  fail "Published docs should describe current Codex plugin-hook trust behavior, not the obsolete dormant-hook gap"
fi

# The skill keeps the rule; the dated harness fact behind it moved to wiki/ when
# harness_portability was shrunk to rules, so each side is pinned where it lives.
doc_has 'document the trust, enablement, reload, or cache-refresh step that makes the hook active' \
  "${REPO_ROOT}/plugins/ai_dev/skills/harness_portability/SKILL.md" ||
  fail "harness_portability should carry the runtime-loading rule for plugin-bundled hooks"

doc_has 'skipped until the user reviews and trusts the current definition' \
  "${REPO_ROOT}/wiki/concepts/hook-surface-portability.md" \
  "${REPO_ROOT}/wiki/entities/openai-codex.md" ||
  fail "wiki should document current Codex plugin-hook trust behavior"

if jq -e 'has("hooks")' "${REPO_ROOT}/plugins/ai_dev/.claude-plugin/plugin.json" >/dev/null; then
  fail "Claude plugin manifest should not declare a hooks key"
fi

if find "${REPO_ROOT}/plugins/ai_dev/skills" -maxdepth 1 -type d -name 'task_charter' | grep -q .; then
  fail "task_charter skill should not exist"
fi

git -C "$REPO_ROOT" diff --quiet -- deployment/deployment.conf ||
  fail "deployment.conf should remain unchanged"
git -C "$REPO_ROOT" diff --quiet -- \
  plugins/ai_dev/skills/task_create/SKILL.md \
  plugins/ai_dev/skills/task_check/SKILL.md \
  plugins/ai_dev/skills/task_implement/SKILL.md ||
  fail "Manual task-chain skills should remain unchanged by this hook task"

deploy_project="${TMP_ROOT}/deploy project"
mkdir -p "$deploy_project"
deploy_out="${TMP_ROOT}/deploy.out"
"$DEPLOY" --project-dir "$deploy_project" --target codex --type hook --dry-run >"$deploy_out"
grep -q 'would-copy.*\.codex/hooks/charter_guardrail\.sh' "$deploy_out" ||
  fail "Codex dry-run should copy charter_guardrail.sh into the Codex hooks dir"
grep -q 'would-merge.*\.codex/hooks\.json' "$deploy_out" ||
  fail "Codex dry-run should merge hooks into .codex/hooks.json"
grep -q "would-rewrite.*${deploy_project}/.codex/hooks/" "$deploy_out" ||
  fail "Codex dry-run should rewrite ./hooks/ commands to the deployed absolute hooks dir"
if grep -q 'Hook deployment not implemented for codex' "$deploy_out"; then
  fail "Codex hook deployment should not fall through to the unimplemented skip"
fi

# --- Fast path stays jq-independent ------------------------------------------
# The hook now fires on every Bash call. A command that never names the charter
# must exit before the jq requirement, so a jq-less machine is not bricked; a
# command that does name the charter with jq gone fails closed with an
# actionable message.

clean_cmd_json="$(bash_json "$charter_repo" 'echo hello world')"
set +e
printf '%s' "$clean_cmd_json" | env -i PATH="$nojq_bin" /bin/sh "$HOOK" >/dev/null 2>&1
rc_nojq_clean=$?
set -e
[[ "$rc_nojq_clean" -eq 0 ]] ||
  fail "Fast path should exit 0 without jq for a command that never names the charter, got rc=$rc_nojq_clean"

charter_cmd_json="$(bash_json "$charter_repo" 'echo x > CHARTER.md')"
set +e
nojq_err="$(printf '%s' "$charter_cmd_json" | env -i PATH="$nojq_bin" /bin/sh "$HOOK" 2>&1 >/dev/null)"
rc_nojq_charter=$?
set -e
[[ "$rc_nojq_charter" -eq 2 ]] ||
  fail "A charter-naming command with jq unavailable should fail closed (rc 2), got rc=$rc_nojq_charter"
grep -q 'jq' <<< "$nojq_err" ||
  fail "The jq-missing block should name jq in its reason"

printf 'ok\n'
