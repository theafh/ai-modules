#!/usr/bin/env bash
# discover_tasks.sh — print the tasks directory path on stdout.
#
# Resolution order from CWD:
#   1. `git rev-parse --show-toplevel` → use that repo root.
#   2. Walk up from CWD looking for a project marker:
#        .git, package.json, pyproject.toml, Cargo.toml, go.mod,
#        CLAUDE.md, AGENTS.md, Makefile, .project-root
#      Use the closest level that holds one.
#   3. Fall back to CWD.
#
# Then print "<root>/tasks" on stdout.
#
# Exit codes:
#   0  the tasks/ directory exists at the printed path
#   1  the tasks/ directory does not exist yet; caller should run
#      `init_tasks.sh <printed-path>` to scaffold it
#   2  bad argument
#
# Usage:
#   path=$(scripts/discover_tasks.sh) || scripts/init_tasks.sh "$path"

set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
discover_tasks.sh — print the tasks directory path on stdout.

Resolution order from CWD:
  1. `git rev-parse --show-toplevel` → use that repo root.
  2. Walk up from CWD looking for any of:
       .git, package.json, pyproject.toml, Cargo.toml, go.mod,
       CLAUDE.md, AGENTS.md, Makefile, .project-root
     Use the closest level that holds one.
  3. Fall back to CWD.

Prints "<root>/tasks" and exits 0 when that directory exists, exit 1
when it does not yet exist (caller should scaffold via init_tasks.sh).

Usage:
  path=$(scripts/discover_tasks.sh) || scripts/init_tasks.sh "$path"
USAGE
    exit 0
    ;;
  '')
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
esac

MARKERS=(.git package.json pyproject.toml Cargo.toml go.mod CLAUDE.md AGENTS.md Makefile .project-root)

abs() {
  if [[ -d "$1" ]]; then
    (cd "$1" && pwd -P)
  else
    printf '%s' "$1"
  fi
}

root=""

# 1. Prefer the git toplevel when CWD is inside a working tree.
if git_top=$(git rev-parse --show-toplevel 2>/dev/null); then
  root="$git_top"
fi

# 2. Walk up looking for project markers when no git root was found.
if [[ -z "$root" ]]; then
  level=$(abs "$PWD")
  while true; do
    for marker in "${MARKERS[@]}"; do
      if [[ -e "$level/$marker" ]]; then
        root="$level"
        break 2
      fi
    done
    parent=$(dirname "$level")
    [[ "$parent" == "$level" ]] && break
    level="$parent"
  done
fi

# 3. Fall back to CWD.
[[ -z "$root" ]] && root=$(abs "$PWD")

tasks_dir="$root/tasks"
printf '%s\n' "$tasks_dir"

[[ -d "$tasks_dir" ]] || exit 1
exit 0
