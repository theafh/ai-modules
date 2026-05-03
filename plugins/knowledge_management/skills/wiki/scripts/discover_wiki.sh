#!/usr/bin/env bash
# discover_wiki.sh — print the wiki path on stdout.
#
# Discovery looks ONLY at the current working directory:
#   1. ./wiki/        → print "$PWD/wiki"
#   2. ./.no_wiki     → print "$HOME/wiki"
#   3. neither        → exit 2 (caller must ask the user)
#
# `.no_wiki` is the explicit opt-out. Drop an empty file by that name
# in any directory you do not want a local wiki for, and discovery routes
# to the global home wiki instead.
#
# With --check, additionally exits 1 if the chosen path does not exist
# on disk so the caller can decide whether to init it (see init_wiki.sh).
#
# Usage:
#   path=$(scripts/discover_wiki.sh) || ask_the_user
#   path=$(scripts/discover_wiki.sh --check) || scripts/init_wiki.sh "$path"

set -euo pipefail

CHECK=false
case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
discover_wiki.sh — print the wiki path on stdout.

Discovery (current working directory only):
  1. ./wiki/        → print "$PWD/wiki"
  2. ./.no_wiki     → print "$HOME/wiki"
  3. neither        → exit 2 (caller must ask the user)

Options:
  --check     Exit 1 if the chosen path does not exist on disk
  -h, --help  Show this help

Usage:
  path=$(scripts/discover_wiki.sh) || ask_the_user
  path=$(scripts/discover_wiki.sh --check) || scripts/init_wiki.sh "$path"
USAGE
    exit 0
    ;;
  --check)
    CHECK=true
    ;;
  '')
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 2
    ;;
esac

if [[ -d "./wiki" ]]; then
  path="$PWD/wiki"
elif [[ -f "./.no_wiki" ]]; then
  path="$HOME/wiki"
else
  echo "no wiki/ or .no_wiki in current directory; ask the user to choose" >&2
  exit 2
fi

printf '%s\n' "$path"

if $CHECK && [[ ! -d "$path" ]]; then
  exit 1
fi
