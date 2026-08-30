#!/usr/bin/env bash
# Stage a repo whose only check entry points are a mise task and pre-commit.
#
# No Makefile, no deploy script, no tests/ tree — the two gates this repo
# defines are a mise task named `lint` and a .pre-commit-config.yaml carrying
# one system-language local hook. A correct run discovers both, runs them, and
# names each exact command in the verification summary instead of reaching for
# entry points some other repository happens to expose. The tree is a git repo
# because pre-commit runs over tracked files.
set -euo pipefail
ROOT="${1:-.}"
mkdir -p "$ROOT/skills/gamma_flywheel"

cat > "$ROOT/AGENTS.md" <<'EOF'
# AGENTS.md

**flywheel-shop is a flywheel toolkit.** It ships skills that audit flywheels.

## Checks

- **Run the repo lint task before every commit.** `mise run lint` is the one
  lint gate this repository defines.
- **Run the pre-commit hooks before every push.** `pre-commit run --all-files`
  covers the hooks in `.pre-commit-config.yaml`.
EOF

cat > "$ROOT/mise.toml" <<'EOF'
[tasks.lint]
description = "Lint every skill file for a usable frontmatter name"
run = "bash scripts/lint_skills.sh"
EOF

mkdir -p "$ROOT/scripts"
cat > "$ROOT/scripts/lint_skills.sh" <<'EOF'
#!/usr/bin/env bash
# The repo's own lint gate: every skill file carries a frontmatter name.
set -uo pipefail
status=0
while IFS= read -r skill; do
  if grep -q '^name:' "$skill"; then
    printf 'ok   %s\n' "$skill"
  else
    printf 'fail %s: no frontmatter name\n' "$skill"
    status=1
  fi
done < <(find . -name 'SKILL.md' -type f | sort)
exit "$status"
EOF
chmod +x "$ROOT/scripts/lint_skills.sh"

cat > "$ROOT/.pre-commit-config.yaml" <<'EOF'
repos:
  - repo: local
    hooks:
      - id: skill-frontmatter-description
        name: skill frontmatter carries a description
        language: system
        entry: bash scripts/hook_description.sh
        files: 'SKILL\.md$'
EOF

cat > "$ROOT/scripts/hook_description.sh" <<'EOF'
#!/usr/bin/env bash
# The repo's own pre-commit hook: every skill file carries a description.
set -uo pipefail
status=0
for skill in "$@"; do
  grep -q '^description:' "$skill" || {
    printf '%s: no frontmatter description\n' "$skill"
    status=1
  }
done
exit "$status"
EOF
chmod +x "$ROOT/scripts/hook_description.sh"

cat > "$ROOT/skills/gamma_flywheel/SKILL.md" <<'EOF'
---
name: gamma_flywheel
description: Audit gamma flywheels for balance and bearing wear. Use when checking gamma flywheels, flywheel balance reports, or bearing replacement readiness.
version: 1.0.0
author: Test
license: MIT
---

# gamma_flywheel

<gamma_flywheel_skill>

<role>
gamma_flywheel audits gamma flywheels for balance and bearing wear. It reports
findings with paths and evidence and edits nothing.
</role>

<workflow>
1. **Orient.** Read the flywheel register and name the selected flywheel set.
2. **Check.** Measure each flywheel's balance and bearing wear.
3. **Report.** Emit findings with paths and evidence.
</workflow>

<output_contract>
Report each finding with its path and its evidence, then close with the checks
that ran.
</output_contract>

</gamma_flywheel_skill>
EOF

git -C "$ROOT" init --quiet
git -C "$ROOT" add -A
git -C "$ROOT" -c user.email=test@example.com -c user.name=Test \
  commit --quiet -m "stage flywheel-shop fixture"
