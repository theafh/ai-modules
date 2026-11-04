#!/usr/bin/env bash
# Regression coverage for --update: log-driven replay of every recorded scope,
# with its scope narrowing, --target/--type filters, vanished-scope drop,
# foreign-checkout skip, orphan reporting, dry-run, and documentation claims.
set -euo pipefail

if [[ "${TEST_VENDOR:-}" == "cursor" ]] || [[ "${1:-}" == "--vendor" && "${2:-}" == "cursor" ]]; then
  printf '%s\n' \
    "update_run.sh is a deterministic script harness; --vendor is unsupported." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
# Invoke the deploy script on the stock bash the floor targets.
DEPLOY_BASH="/bin/bash"
DEPLOY_LOG="${REPO_ROOT}/deployment/deployed_artefacts.log"
SCRATCH="$(mktemp -d)"
LOG_BACKUP="${SCRATCH}/deployed_artefacts.log.backup"
LOG_HAD_FILE=false
HOME_DIR="${SCRATCH}/home"
PROJECT_DIR="${SCRATCH}/project"
SKILL_ONE="task_create"
SKILL_TWO="spr"
SKILL_ONE_SRC="${REPO_ROOT}/plugins/ai_dev/skills/${SKILL_ONE}"
STYLE_SRC="${REPO_ROOT}/styles/natural-language.md"
CURSOR_RULE_NAME="natural-language.mdc"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "expected directory: $1"
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  [[ "$got" == "$want" ]] || fail "$msg (got='$got' want='$want')"
}

assert_contains() {
  local text="$1" pattern="$2" msg="$3"
  printf '%s\n' "$text" | grep -Fq -- "$pattern" || fail "$msg (missing '$pattern')"
}

assert_log_has() {
  grep -Fq -- "$1" "$DEPLOY_LOG" || fail "expected the deploy log to keep $1"
}

assert_log_lacks() {
  if grep -Fq -- "$1" "$DEPLOY_LOG"; then
    fail "expected the deploy log to drop $1"
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

deploy() {
  HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" "$@"
}

update() {
  HOME="$HOME_DIR" "$DEPLOY_BASH" "$DEPLOY_SCRIPT" --update "$@"
}

backup_count() {
  find "$HOME_DIR" -maxdepth 1 -type d -name '.claude_*' 2>/dev/null | wc -l | tr -d ' '
}

mkdir -p "$HOME_DIR" "$PROJECT_DIR"

# ---------------------------------------------------------------------------
# Static acceptance: --help, Makefile, and the documentation the mode changes.
# ---------------------------------------------------------------------------
help_out="$("$DEPLOY_BASH" "$DEPLOY_SCRIPT" --help)"
assert_contains "$help_out" '--update' "--help does not list --update"
help_flat="$(printf '%s\n' "$help_out" | tr '\n' ' ' | tr -s ' ')"
assert_contains "$help_flat" 'unless used with --uninstall or --update' \
  "--help --type line does not name --uninstall and --update"

make_help="$(make -C "$REPO_ROOT" help)"
printf '%s\n' "$make_help" | grep -Eq '^  update[[:space:]]' ||
  fail "make help does not list an update target"
make_n="$(make -C "$REPO_ROOT" -n update)"
assert_contains "$make_n" './deployment/deployment.sh --update' \
  "make -n update does not print the update command"

deploy_readme="${REPO_ROOT}/deployment/README.md"
assert_file "$deploy_readme"
grep -Fq '| `--update` |' "$deploy_readme" ||
  fail "deployment/README.md Flags table has no --update row"
grep -Fq '`--uninstall`, `--update`, and standalone `--clear-backups` are maintenance modes' "$deploy_readme" ||
  fail "deployment/README.md Run It intro does not list update as a no-scope mode"
grep -Fq 'unless used with `--uninstall` or `--update`' "$deploy_readme" ||
  fail "deployment/README.md --type row does not name update"
grep -Fq '`--update` and `--uninstall` are log-driven maintenance modes' "$deploy_readme" ||
  fail "deployment/README.md explicit-scope paragraph does not name update"
grep -Fq '`--update` and `--uninstall` are the two readers of this log' "$deploy_readme" ||
  fail "deployment/README.md log section does not describe update beside uninstall"
if grep -Fq 'Re-run the script after editing a source artifact to refresh its deployed copy.' "$deploy_readme"; then
  fail "deployment/README.md still carries the superseded refresh sentence"
fi
grep -Fq 'Run `make update` after editing a source artefact' "$deploy_readme" ||
  fail "deployment/README.md refresh passage does not name make update"

grep -Fq 'make update' "${REPO_ROOT}/README.md" ||
  fail "root README.md Makefile block does not list make update"

for instruction_file in CLAUDE.md AGENTS.md; do
  grep -F '`make update`' "${REPO_ROOT}/${instruction_file}" |
    grep -Fq 'Run only when the user asks for it.' ||
    fail "${instruction_file} Common tasks lacks make update with its guard"
done

wiki_page="${REPO_ROOT}/wiki/concepts/deployment-model.md"
grep -Fq 'update and uninstall replay that log' "$wiki_page" ||
  fail "wiki deployment-model page does not name update beside uninstall"
grep -Fq 'an update path' "$wiki_page" ||
  fail "wiki deployment-model page does not name update in the script capability list"

grep -Fq 'update_run.sh' "${REPO_ROOT}/tests/deployment/run_all.sh" ||
  fail "tests/deployment/run_all.sh does not run update_run.sh"
grep -Fq 'update_run.sh' "${REPO_ROOT}/tests/README.md" ||
  fail "tests/README.md does not describe update_run.sh"
grep -Fq 'update_run.sh' "${REPO_ROOT}/tests/CLAUDE.md" ||
  fail "tests/CLAUDE.md does not describe update_run.sh"

# ---------------------------------------------------------------------------
# A missing deploy log reports and exits zero.
# ---------------------------------------------------------------------------
set +e
missing_out="$(update 2>&1)"
missing_rc=$?
set -e
assert_eq "$missing_rc" "0" "--update without a deploy log should exit zero"
assert_contains "$missing_out" 'No deploy log found' \
  "--update without a deploy log should report the missing log"

# ---------------------------------------------------------------------------
# --update rejects --uninstall and names both flags.
# ---------------------------------------------------------------------------
set +e
combo_out="$(update --uninstall 2>&1)"
combo_rc=$?
set -e
[[ "$combo_rc" -ne 0 ]] || fail "--update --uninstall should exit non-zero"
assert_contains "$combo_out" '--update' "--update --uninstall error should name --update"
assert_contains "$combo_out" '--uninstall' "--update --uninstall error should name --uninstall"

# ---------------------------------------------------------------------------
# Main replay: a global skill deploy and a project Cursor style deploy are
# both restored from the checkout, with one fresh backup of the global root
# and no cross-product writes into the project.
# ---------------------------------------------------------------------------
deploy --global --target claude --type skill --only "${SKILL_ONE},${SKILL_TWO}" >/dev/null
deploy --project-dir "$PROJECT_DIR" --target cursor --type style >/dev/null

GLOBAL_SKILL="${HOME_DIR}/.claude/skills/${SKILL_ONE}"
PROJECT_RULE="${PROJECT_DIR}/.cursor/rules/${CURSOR_RULE_NAME}"
assert_file "${GLOBAL_SKILL}/SKILL.md"
assert_file "${HOME_DIR}/.claude/skills/${SKILL_TWO}/SKILL.md"
assert_file "$PROJECT_RULE"
cp "${SKILL_ONE_SRC}/SKILL.md" "${SCRATCH}/expected-skill.md"
cp "$PROJECT_RULE" "${SCRATCH}/expected-rule.mdc"

rm -f "${GLOBAL_SKILL}/SKILL.md"
printf '%s\n' 'tampered' > "$PROJECT_RULE"

backups_before="$(backup_count)"
update_out="$(update)"
backups_after="$(backup_count)"

cmp -s "${SCRATCH}/expected-skill.md" "${GLOBAL_SKILL}/SKILL.md" ||
  fail "--update did not restore the deleted global skill file"
cmp -s "${SCRATCH}/expected-rule.mdc" "$PROJECT_RULE" ||
  fail "--update did not restore the project Cursor rule byte for byte"
assert_eq "$((backups_after - backups_before))" "1" \
  "--update should create exactly one new backup of the global target root"
assert_contains "$update_out" 'global: replayed' \
  "closing summary does not name the global scope as replayed"
assert_contains "$update_out" "${PROJECT_DIR}: replayed" \
  "closing summary does not name the project scope as replayed"
[[ ! -e "${PROJECT_DIR}/.claude" ]] ||
  fail "project replay created a .claude directory"
[[ ! -e "${PROJECT_DIR}/.cursor/skills" ]] ||
  fail "project replay created a .cursor/skills directory"

# ---------------------------------------------------------------------------
# --update --dry-run names each scope it would replay and writes nothing.
# ---------------------------------------------------------------------------
rm -f "${GLOBAL_SKILL}/SKILL.md"
printf '%s\n' 'tampered-again' > "$PROJECT_RULE"
home_before="$(snapshot_tree "$HOME_DIR")"
project_before="$(snapshot_tree "$PROJECT_DIR")"
log_before="$(sha256_of "$DEPLOY_LOG")"

dry_out="$(update --dry-run)"
assert_contains "$dry_out" 'global: would replay' \
  "dry run does not name the global scope it would replay"
assert_contains "$dry_out" "${PROJECT_DIR}: would replay" \
  "dry run does not name the project scope it would replay"
assert_eq "$(snapshot_tree "$HOME_DIR")" "$home_before" \
  "dry run changed the scratch home"
assert_eq "$(snapshot_tree "$PROJECT_DIR")" "$project_before" \
  "dry run changed the scratch project"
assert_eq "$(sha256_of "$DEPLOY_LOG")" "$log_before" \
  "dry run changed the deploy log"

# ---------------------------------------------------------------------------
# A vanished project scope is reported and kept on a dry run, then reported,
# dropped from the log, and left absent on a real run.
# ---------------------------------------------------------------------------
GONE_PROJECT="${SCRATCH}/gone-project"
mkdir -p "$GONE_PROJECT"
deploy --project-dir "$GONE_PROJECT" --target cursor --type style >/dev/null
GONE_RULE="${GONE_PROJECT}/.cursor/rules/${CURSOR_RULE_NAME}"
assert_file "$GONE_RULE"
assert_log_has "$GONE_RULE"
rm -rf "$GONE_PROJECT"

gone_dry="$(update --dry-run)"
assert_contains "$gone_dry" "${GONE_PROJECT}: would drop" \
  "dry run does not report the vanished scope it would drop"
assert_log_has "$GONE_RULE"
[[ ! -e "$GONE_PROJECT" ]] || fail "dry run recreated the vanished project"

gone_out="$(update)"
assert_contains "$gone_out" "${GONE_PROJECT}: dropped" \
  "real run does not report the vanished scope it dropped"
assert_log_lacks "$GONE_RULE"
[[ ! -e "$GONE_PROJECT" ]] || fail "update recreated the vanished project"
cmp -s "${SCRATCH}/expected-skill.md" "${GLOBAL_SKILL}/SKILL.md" ||
  fail "the real run after the dry run did not restore the global skill"
cmp -s "${SCRATCH}/expected-rule.mdc" "$PROJECT_RULE" ||
  fail "the real run after the dry run did not restore the project rule"

# ---------------------------------------------------------------------------
# A scope flag keeps another vanished scope's entries in the log.
# ---------------------------------------------------------------------------
GONE_PROJECT_TWO="${SCRATCH}/gone-project-two"
mkdir -p "$GONE_PROJECT_TWO"
deploy --project-dir "$GONE_PROJECT_TWO" --target cursor --type style >/dev/null
GONE_RULE_TWO="${GONE_PROJECT_TWO}/.cursor/rules/${CURSOR_RULE_NAME}"
assert_log_has "$GONE_RULE_TWO"
rm -rf "$GONE_PROJECT_TWO"

update --project-dir "$PROJECT_DIR" >/dev/null
assert_log_has "$GONE_RULE_TWO"
[[ ! -e "$GONE_PROJECT_TWO" ]] || fail "scope-narrowed update recreated the vanished project"

# ---------------------------------------------------------------------------
# A group whose sources all live in another checkout is reported and left
# byte for byte untouched.
# ---------------------------------------------------------------------------
FOREIGN_SCOPE="${SCRATCH}/foreign-scope"
mkdir -p "${FOREIGN_SCOPE}/.cursor/rules"
FOREIGN_RULE="${FOREIGN_SCOPE}/.cursor/rules/foreign.mdc"
printf '%s\n' 'foreign-original' > "$FOREIGN_RULE"
printf '%s\t%s\t%s\t%s\n' "$FOREIGN_RULE" cursor style \
  '/some/other/checkout/styles/natural-language.md' >> "$DEPLOY_LOG"

foreign_out="$(update)"
assert_contains "$foreign_out" "${FOREIGN_SCOPE} cursor style" \
  "foreign group is not named by its scope, target, and type"
assert_contains "$foreign_out" 'deployed from another checkout' \
  "foreign group is not reported as deployed from another checkout"
printf '%s\n' 'foreign-original' | cmp -s - "$FOREIGN_RULE" ||
  fail "update changed a foreign-checkout deployed path"
assert_log_has "$FOREIGN_RULE"

# ---------------------------------------------------------------------------
# A mixed group replays its live artefact and leaves its foreign path alone.
# ---------------------------------------------------------------------------
MIXED_PROJECT="${SCRATCH}/mixed-project"
mkdir -p "$MIXED_PROJECT"
deploy --project-dir "$MIXED_PROJECT" --target cursor --type style >/dev/null
MIXED_RULE="${MIXED_PROJECT}/.cursor/rules/${CURSOR_RULE_NAME}"
MIXED_FOREIGN="${MIXED_PROJECT}/.cursor/rules/foreign-mixed.mdc"
printf '%s\n' 'foreign-mixed-original' > "$MIXED_FOREIGN"
printf '%s\t%s\t%s\t%s\n' "$MIXED_FOREIGN" cursor style \
  '/elsewhere/checkout/styles/natural-language.md' >> "$DEPLOY_LOG"
printf '%s\n' 'tampered-mixed' > "$MIXED_RULE"

set +e
mixed_out="$(update 2>&1)"
mixed_rc=$?
set -e
assert_eq "$mixed_rc" "0" "mixed-group update should exit zero"
cmp -s "${SCRATCH}/expected-rule.mdc" "$MIXED_RULE" ||
  fail "mixed-group update did not refresh the live artefact"
printf '%s\n' 'foreign-mixed-original' | cmp -s - "$MIXED_FOREIGN" ||
  fail "mixed-group update changed the foreign deployed path"
assert_log_has "$MIXED_FOREIGN"
assert_contains "$mixed_out" "$MIXED_PROJECT" "mixed-group update does not name its scope"

# ---------------------------------------------------------------------------
# An orphan entry beside a live group is reported and kept.
# ---------------------------------------------------------------------------
ORPHAN_SKILL_PATH="${HOME_DIR}/.claude/skills/orphan-skill"
ORPHAN_SOURCE="${REPO_ROOT}/plugins/ai_dev/skills/orphan-skill"
mkdir -p "$ORPHAN_SKILL_PATH"
printf '%s\n' 'orphan-copy' > "${ORPHAN_SKILL_PATH}/SKILL.md"
printf '%s\t%s\t%s\t%s\n' "$ORPHAN_SKILL_PATH" claude skill "$ORPHAN_SOURCE" >> "$DEPLOY_LOG"

orphan_out="$(update)"
assert_contains "$orphan_out" "$ORPHAN_SKILL_PATH" \
  "orphan entry is not reported with its deployed path"
assert_contains "$orphan_out" 'orphan' "orphan entry is not labelled"
assert_file "${ORPHAN_SKILL_PATH}/SKILL.md"
assert_log_has "$ORPHAN_SKILL_PATH"

# ---------------------------------------------------------------------------
# A group whose only entry is an orphan replays nothing and exits zero.
# ---------------------------------------------------------------------------
ORPHAN_PROJECT="${SCRATCH}/orphan-project"
ORPHAN_ONLY_PATH="${ORPHAN_PROJECT}/.claude/skills/orphan-only"
ORPHAN_ONLY_SOURCE="${REPO_ROOT}/plugins/ai_dev/skills/orphan-only"
mkdir -p "$ORPHAN_ONLY_PATH"
printf '%s\n' 'orphan-only-copy' > "${ORPHAN_ONLY_PATH}/SKILL.md"
printf '%s\t%s\t%s\t%s\n' "$ORPHAN_ONLY_PATH" claude skill "$ORPHAN_ONLY_SOURCE" >> "$DEPLOY_LOG"

set +e
orphan_only_out="$(update --project-dir "$ORPHAN_PROJECT" 2>&1)"
orphan_only_rc=$?
set -e
assert_eq "$orphan_only_rc" "0" "orphan-only group update should exit zero"
assert_contains "$orphan_only_out" "$ORPHAN_ONLY_PATH" \
  "orphan-only entry is not reported with its deployed path"
assert_contains "$orphan_only_out" 'no replayable artefact names' \
  "orphan-only group is not reported as skipped"
assert_file "${ORPHAN_ONLY_PATH}/SKILL.md"
assert_log_has "$ORPHAN_ONLY_PATH"

# ---------------------------------------------------------------------------
# A deployed path fitting neither scope form is reported as unrecognized and
# stays in the log.
# ---------------------------------------------------------------------------
UNRECOGNIZED_PATH="${SCRATCH}/unrecognized/settings.json"
printf '%s\t%s\t%s\t%s\n' "$UNRECOGNIZED_PATH" claude style "$STYLE_SRC" >> "$DEPLOY_LOG"

unrecognized_out="$(update)"
assert_contains "$unrecognized_out" "$UNRECOGNIZED_PATH" \
  "unrecognized entry is not reported with its deployed path"
assert_contains "$unrecognized_out" 'unrecognized' \
  "unrecognized entry is not labelled"
assert_log_has "$UNRECOGNIZED_PATH"

# ---------------------------------------------------------------------------
# Scope narrowing restores only the selected scope; --target narrows too.
# ---------------------------------------------------------------------------
rm -f "${GLOBAL_SKILL}/SKILL.md"
printf '%s\n' 'tampered-narrow' > "$PROJECT_RULE"
update --project-dir "$PROJECT_DIR" >/dev/null
cmp -s "${SCRATCH}/expected-rule.mdc" "$PROJECT_RULE" ||
  fail "scope-narrowed update did not restore the project rule"
[[ ! -e "${GLOBAL_SKILL}/SKILL.md" ]] ||
  fail "scope-narrowed update restored the out-of-scope global skill"

printf '%s\n' 'tampered-target' > "$PROJECT_RULE"
update --target cursor >/dev/null
cmp -s "${SCRATCH}/expected-rule.mdc" "$PROJECT_RULE" ||
  fail "--target cursor update did not restore the project rule"
[[ ! -e "${GLOBAL_SKILL}/SKILL.md" ]] ||
  fail "--target cursor update restored the filtered-out global skill"

# ---------------------------------------------------------------------------
# A project that received one skill through --only still holds only that one
# skill after --update, refreshed from the checkout.
# ---------------------------------------------------------------------------
ONLY_PROJECT="${SCRATCH}/only-project"
mkdir -p "$ONLY_PROJECT"
deploy --project-dir "$ONLY_PROJECT" --target claude --type skill --only "$SKILL_ONE" >/dev/null
ONLY_SKILL="${ONLY_PROJECT}/.claude/skills/${SKILL_ONE}"
assert_file "${ONLY_SKILL}/SKILL.md"
[[ ! -e "${ONLY_PROJECT}/.claude/skills/${SKILL_TWO}" ]] ||
  fail "the one-skill project should not hold the second skill before update"
rm -f "${ONLY_SKILL}/SKILL.md"

update --project-dir "$ONLY_PROJECT" >/dev/null
cmp -s "${SKILL_ONE_SRC}/SKILL.md" "${ONLY_SKILL}/SKILL.md" ||
  fail "one-skill project update did not refresh the recorded skill"
[[ ! -e "${ONLY_PROJECT}/.claude/skills/${SKILL_TWO}" ]] ||
  fail "one-skill project update deployed a skill the log did not record"

printf 'Update regression passed\n'
