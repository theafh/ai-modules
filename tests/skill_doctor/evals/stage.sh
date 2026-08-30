#!/usr/bin/env bash
# stage.sh — stage one skill_doctor eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints three name=value lines on stdout, each value already quoted with
# printf %q so the lines are safe to `eval`:
#
#   sandbox_repo=<absolute path to the fake repo the skill should check>
#   skill_path=<absolute path to the SKILL.md the agent should load>
#   prompt=<the user prompt to feed the agent>
#
# Layout: every eval stages under $target as
#   $target/repo              the fake repo whose skills get checked
#   $target/.eval_checksums   sha256 of every staged SKILL.md; grade.sh
#                             recomputes it to prove the check-only contract

set -euo pipefail

eval_id="${1:?eval id required (scope_hub_family|scope_prefix_only|discovery_risky_sibling|scope_single_skill_clean|scope_whole_repo|scope_unresolvable_selector|registration_no_manifest|verification_repo_checks)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/skill_doctor_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/skill_doctor/SKILL.md"

sandbox_repo="$target/repo"
mkdir -p "$sandbox_repo"

case "$eval_id" in
  scope_hub_family)
    "$HERE/fixtures/scope_hub_family/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check the demo family skills in this repository."
    ;;
  scope_prefix_only)
    "$HERE/fixtures/scope_prefix_only/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check the wiki family skills in this repository."
    ;;
  discovery_risky_sibling)
    "$HERE/fixtures/discovery_risky_sibling/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check the good_a, good_b, and risky skills in this repository."
    ;;
  scope_single_skill_clean)
    "$HERE/fixtures/scope_multi_plugin/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check the alpha_widget skill in this repository."
    ;;
  scope_whole_repo)
    "$HERE/fixtures/scope_multi_plugin/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check all skills in this repository."
    ;;
  scope_unresolvable_selector)
    "$HERE/fixtures/scope_multi_plugin/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check the omega_flange skill in this repository."
    ;;
  registration_no_manifest)
    "$HERE/fixtures/registration_no_manifest/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check all skills in this repository."
    ;;
  verification_repo_checks)
    "$HERE/fixtures/verification_repo_checks/setup.sh" "$sandbox_repo" >/dev/null
    prompt="Check the gamma_flywheel skill in this repository."
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

skill_path="$SKILL_MD"

# Checksum manifest backs the "edits nothing" expectation every eval carries.
# Registration files join the SKILL.md files here: a fixture that ships
# plugin.json, marketplace.json, and README.md gives the registration pass
# something it could edit, so the manifest has to cover those too.
find "$sandbox_repo" \
  \( -name 'SKILL.md' -o -name '*.json' -o -name 'README.md' \) -type f -print0 \
  | sort -z \
  | xargs -0 shasum -a 256 > "$target/.eval_checksums"

printf 'sandbox_repo=%s\n' "$(printf %q "$sandbox_repo")"
printf 'skill_path=%s\n'   "$(printf %q "$skill_path")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
