#!/usr/bin/env bash
# init_tasks.sh — create the tasks/ directory and its archive/ subfolder.
#
# Idempotent: succeeds whether the target already exists or not. Refuses
# to clobber a non-directory file at the target path.
#
# Pair with discover_tasks.sh:
#   path=$(scripts/discover_tasks.sh) || scripts/init_tasks.sh "$path"
#
# Usage:
#   init_tasks.sh PATH

set -euo pipefail

case "${1:-}" in
  -h|--help|'')
    cat <<'USAGE'
init_tasks.sh — create the tasks/ directory and its archive/ subfolder.

Usage:
  init_tasks.sh PATH

Idempotent. Refuses to overwrite a non-directory file at the target.

Pair with discover_tasks.sh:
  path=$(scripts/discover_tasks.sh) || scripts/init_tasks.sh "$path"
USAGE
    [[ -z "${1:-}" ]] && exit 2 || exit 0
    ;;
esac

TASKS_DIR="$1"

if [[ -e "$TASKS_DIR" && ! -d "$TASKS_DIR" ]]; then
  echo "refusing to init at $TASKS_DIR (a non-directory file exists there)" >&2
  exit 1
fi

mkdir -p "$TASKS_DIR/archive"

echo "tasks directory ready at $TASKS_DIR"
echo "  open tasks live in     : $TASKS_DIR/"
echo "  implemented + deferred : $TASKS_DIR/archive/"
