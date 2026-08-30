#!/usr/bin/env bash
# Shared helpers for task_auto_check behavioral fixtures.

set -euo pipefail

init_proj() {
  local target=$1
  rm -rf "$target/proj"
  mkdir -p "$target/proj/tasks/archive"
  (
    cd "$target/proj"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    cat > CLAUDE.md <<'EOF'
# Harness project

Use the task-family rules from the skill under test. Keep task files
plain CommonMark and run the bundled task linter after edits.
EOF
  )
}

commit_proj() {
  local target=$1
  (
    cd "$target/proj"
    git add .
    git commit --quiet -m "stage task_auto_check fixture"
  )
}
