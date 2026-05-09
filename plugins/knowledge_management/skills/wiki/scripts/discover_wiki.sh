#!/usr/bin/env bash
# discover_wiki.sh — print the wiki path on stdout, walking up from CWD.
#
# Walk-up discovery (when CWD is at or under $HOME):
#   For each level from CWD up to and including $HOME:
#     1. <level>/.no_wiki present → opted out; skip and continue up.
#     2. <level>/wiki/   present → record as the existing wiki and STOP
#        walking (do not search above an existing wiki).
#     3. neither                  → record as an "available" creation
#        candidate and continue up.
#
# Auto-resolve (exit 0, single path on stdout):
#   - The closest non-opted-out level already has wiki/ (i.e. the very
#     first hit during the walk is an existing wiki) → print that path.
#   - Every visited level was opted out via .no_wiki, all the way up
#     through $HOME → print "$HOME/wiki" (the explicit "use home" chain).
#
# Ask-the-user (exit 2, candidate list on stdout):
#   - Otherwise the climb produced creation candidates the user must
#     choose between. Stdout lists them in walk order, one per line,
#     each prefixed with its kind. Format:
#         AVAILABLE:/Users/foo/projects/myproject/src
#         AVAILABLE:/Users/foo/projects/myproject
#         EXISTING:/Users/foo/wiki                  # only the last entry
#         AVAILABLE:/Users/foo                       # may be EXISTING
#     The caller (skill or agent) parses these and asks the user which
#     to use, then offers `.no_wiki` markers in the AVAILABLE candidates
#     between CWD (inclusive) and the chosen path (exclusive).
#
# Outside-$HOME fallback (CWD is not at or under $HOME):
#   The walk-up does not apply; behave as the pre-walk-up script:
#   - <CWD>/wiki/   → print "$CWD/wiki", exit 0.
#   - <CWD>/.no_wiki → print "$HOME/wiki",  exit 0.
#   - neither         → exit 2 with "AVAILABLE:$CWD" and "AVAILABLE:$HOME"
#     so the caller can ask the user.
#
# `.no_wiki` is the explicit opt-out marker. Drop an empty file by that
# name in any directory you do not want a local wiki for, and the walk
# skips that level. Place at an existing `<wiki-path>/.no_wiki` to
# retire that wiki dir without deleting it.
#
# With --check, additionally exits 1 if the auto-resolved path does not
# exist on disk (only meaningful in the auto-resolve case; ignored when
# exiting 2 for the ask-the-user case).
#
# Usage:
#   if WIKI=$(scripts/discover_wiki.sh); then
#       : # auto-resolved; $WIKI is the wiki path
#   else
#       case $? in
#           2) candidates="$WIKI"; ask_the_user_with "$candidates" ;;
#           *) exit 1 ;;
#       esac
#   fi
#
#   path=$(scripts/discover_wiki.sh --check) || scripts/init_wiki.sh "$path"

set -euo pipefail

CHECK=false
case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
discover_wiki.sh — print the wiki path on stdout, walking up from CWD.

Walk-up discovery (when CWD is at or under $HOME):
  For each level from CWD up to and including $HOME:
    1. <level>/.no_wiki present → opted out; skip and continue up.
    2. <level>/wiki/   present → record as the existing wiki and STOP
       walking (do not search above an existing wiki).
    3. neither                  → record as an "available" creation
       candidate and continue up.

Auto-resolve (exit 0, single path on stdout):
  - The closest non-opted-out level already has wiki/.
  - Every visited level was opted out via .no_wiki up through $HOME →
    print "$HOME/wiki".

Ask-the-user (exit 2, candidate list on stdout):
  - Otherwise stdout lists each candidate in walk order, one per line,
    prefixed AVAILABLE: or EXISTING:. The caller asks the user which
    to use and offers .no_wiki markers in the AVAILABLE candidates
    between CWD (inclusive) and the chosen path (exclusive).

Outside-$HOME fallback (CWD not at or under $HOME):
  - <CWD>/wiki/   → print "$CWD/wiki",  exit 0.
  - <CWD>/.no_wiki → print "$HOME/wiki", exit 0.
  - neither         → exit 2 with two AVAILABLE candidates ($CWD, $HOME).

Options:
  --check     Exit 1 if the auto-resolved path does not exist on disk.
  -h, --help  Show this help.
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

abs() {
  # Print the canonical absolute path of $1, falling back to $1 verbatim
  # if the directory cannot be entered (e.g. $HOME unset on a CI box).
  if [[ -d "$1" ]]; then
    (cd "$1" && pwd -P)
  else
    printf '%s' "$1"
  fi
}

cwd=$(abs "$PWD")
home=$(abs "$HOME")

under_home=false
case "$cwd" in
  "$home"|"$home"/*) under_home=true ;;
esac

# Build the ladder: every ancestor from CWD up to (and including) $HOME
# when under home; otherwise just CWD itself.
ladder=()
if $under_home; then
  level="$cwd"
  while true; do
    ladder+=("$level")
    [[ "$level" == "$home" ]] && break
    parent=$(dirname "$level")
    [[ "$parent" == "$level" ]] && break
    level="$parent"
  done
else
  ladder=("$cwd")
fi

# Walk the ladder, building candidates. EXISTING terminates the walk.
candidates=()
for level in "${ladder[@]}"; do
  if [[ -f "$level/.no_wiki" ]]; then
    continue
  fi
  if [[ -d "$level/wiki" ]]; then
    candidates+=("EXISTING:$level/wiki")
    break
  fi
  candidates+=("AVAILABLE:$level")
done

# Auto-resolution paths.
auto=""
if [[ ${#candidates[@]} -eq 0 ]]; then
  # Every level was opted out (or fallback: CWD has .no_wiki and we're
  # outside $HOME). Use the global home wiki.
  auto="$home/wiki"
elif [[ "${candidates[0]}" == EXISTING:* ]]; then
  # Closest non-opted-out level already has a wiki — use it.
  auto="${candidates[0]#EXISTING:}"
fi

if [[ -n "$auto" ]]; then
  printf '%s\n' "$auto"
  if $CHECK && [[ ! -d "$auto" ]]; then
    exit 1
  fi
  exit 0
fi

# Outside-$HOME single-CWD fallback when CWD has neither wiki/ nor .no_wiki:
# emit $CWD plus $HOME as the two creation choices.
if ! $under_home; then
  candidates+=("AVAILABLE:$home")
fi

echo "wiki location is undecided; the caller must ask the user to choose" >&2
printf '%s\n' "${candidates[@]}"
exit 2
