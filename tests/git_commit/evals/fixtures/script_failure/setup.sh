#!/usr/bin/env bash
# Eval 5 fixture: stage a sandbox where prepare_commit_context.sh
# exits non-zero so the skill must use its fallback discipline.
#
# Self-contained: this fixture copies the git_commit skill into
# $target/skill_under_test/ and overwrites the prepare script with a
# failing stub. No runner-side wiring is required — the agent is
# pointed at $target/skill_under_test/SKILL.md and loads the stubbed
# scripts naturally. The constraint that the skill-creator skill is
# read-only is therefore irrelevant for this eval; we copy the
# git_commit plugin skill, which is not read-only.
#
# Layout staged at $1:
#   repo/                       fresh git repo with one modified file
#   skill_under_test/           full copy of git_commit with prepare stubbed
#   .eval_started_at            timestamp marker the grader uses for the
#                                 TMPDIR-context-cleanup check

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
rm -rf "$target"
mkdir -p "$target"

# 1. Sandbox repo with one modified file (mirrors eval 1's working tree).
init_sandbox "$target/repo"
(
    cd "$target/repo"
    printf 'updated\n' > seed.txt
)

# 2. Per-sandbox copy of the git_commit skill with prepare stubbed out.
#    The skill being copied is the git_commit plugin skill — NOT the
#    skill-creator skill, which is read-only for this harness. Resolve
#    the repo root via git from this fixture's location, then look up
#    the plugin skill from there; this is robust to changes in the
#    `tests/` tree depth.
HARNESS_REPO_ROOT="$(git -C "$THIS_DIR" rev-parse --show-toplevel)"
SKILL_SRC="$HARNESS_REPO_ROOT/plugins/ai_dev/skills/git_commit"
if [[ ! -d "$SKILL_SRC" ]]; then
  echo "fixture: cannot find git_commit skill at $SKILL_SRC" >&2
  exit 1
fi
cp -R "$SKILL_SRC" "$target/skill_under_test"

cat > "$target/skill_under_test/scripts/prepare_commit_context.sh" <<'EOF'
#!/usr/bin/env bash
echo "simulated failure for eval 5 fallback test" >&2
exit 1
EOF
chmod +x "$target/skill_under_test/scripts/prepare_commit_context.sh"

# 3. Timestamp marker — grader uses this to scope its TMPDIR
#    context-cleanup check to files created after staging.
: > "$target/.eval_started_at"

echo "Eval 5 sandbox staged at $target"
echo "  skill (prepare stubbed): $target/skill_under_test"
echo "  repo to commit in:       $target/repo"
