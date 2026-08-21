#!/usr/bin/env bash
# discover_wiki.sh — print the wiki path on stdout, walking up from CWD.
#
# A directory is recognised as a wiki when its basename contains "wiki"
# (case-insensitive) AND at least two of SCHEMA.md / index.md / log.md
# exist directly inside it AND it carries no .no_wiki opt-out.
#
# This discovery mirrors lint.py's discover_wiki(): same predicate, same
# walk-up, same lexical child order, both skipping dot-directories when
# scanning a level's children, and the same optional positional wiki path.
# Change one implementation and change the sibling with it.
#
# CWD short-circuit (exit 0): when CWD is itself a wiki by that test, print
# CWD and stop — before any walk-up.
#
# Walk-up discovery (when CWD is at or under $HOME):
#   For each level from CWD up to and including $HOME:
#     1. <level>/.no_wiki present → opted out; skip and continue up.
#     2. a child directory recognised as a wiki (lexically first wins) →
#        record as the existing wiki and STOP walking.
#     3. neither                  → record as an "available" creation
#        candidate and continue up.
#
# Auto-resolve (exit 0, single path on stdout):
#   - CWD is itself a wiki (short-circuit), or the closest non-opted-out
#     level already holds a recognised wiki → print that path.
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
#   - a recognised wiki child of CWD → print it, exit 0.
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
# Chosen-path handoff (WIKI_PATH argument):
#   A WIKI_PATH argument skips discovery and answers for that path alone,
#   mirroring lint.py's optional positional wiki_path: an existing
#   directory prints its canonical path and exits 0, a missing one exits 1
#   with a message on stderr. The wiki predicate is deliberately not
#   applied, so a caller can hand back the candidate the user picked from
#   an exit-2 list — an AVAILABLE: level included — instead of re-running
#   discovery, which would only reproduce the same ambiguous list.
#
# Exit codes:
#   0  a single resolved path on stdout
#   1  --check found the auto-resolved path missing, or the given
#      WIKI_PATH does not exist on disk
#   2  ambiguous: candidate list on stdout, and the caller asks the user
#   3  usage error: unknown flag or unsupported argument shape, message on
#      stderr and nothing on stdout, so a caller never reads a usage
#      mistake as an empty candidate list
#
# Argument shapes: no arguments, --check, WIKI_PATH, WIKI_PATH --check,
# and -h / --help. Every other shape exits 3.
#
# Usage:
#   if WIKI=$(scripts/discover_wiki.sh); then
#       : # auto-resolved; $WIKI is the wiki path
#   else
#       rc=$?
#       case $rc in
#           2) candidates="$WIKI"; ask_the_user_with "$candidates" ;;
#           *) exit "$rc" ;;   # 1 = path missing, 3 = usage error
#       esac
#   fi
#
#   path=$(scripts/discover_wiki.sh --check) || scripts/init_wiki.sh "$path"
#
#   # Once the user picks a candidate, adopt that path directly:
#   WIKI=$(scripts/discover_wiki.sh "$chosen")

set -euo pipefail

CHECK=false
WIKI_ARG=""

print_help() {
  cat <<'USAGE'
discover_wiki.sh — print the wiki path on stdout, walking up from CWD.

A directory is a wiki when its basename contains "wiki" (case-insensitive)
AND >=2 of SCHEMA.md / index.md / log.md exist in it AND it has no .no_wiki.

CWD short-circuit (exit 0): if CWD is itself a wiki, print CWD and stop.

Walk-up discovery (when CWD is at or under $HOME):
  For each level from CWD up to and including $HOME:
    1. <level>/.no_wiki present → opted out; skip and continue up.
    2. a child dir recognised as a wiki (lexically first) → record as the
       existing wiki and STOP walking.
    3. neither                  → record as an "available" creation
       candidate and continue up.

Auto-resolve (exit 0, single path on stdout):
  - CWD is itself a wiki, or the closest non-opted-out level holds one.
  - Every visited level was opted out via .no_wiki up through $HOME →
    print "$HOME/wiki".

Ask-the-user (exit 2, candidate list on stdout):
  - Otherwise stdout lists each candidate in walk order, one per line,
    prefixed AVAILABLE: or EXISTING:. The caller asks the user which
    to use and offers .no_wiki markers in the AVAILABLE candidates
    between CWD (inclusive) and the chosen path (exclusive).

Outside-$HOME fallback (CWD not at or under $HOME):
  - a recognised wiki child of CWD → print it,  exit 0.
  - <CWD>/.no_wiki → print "$HOME/wiki", exit 0.
  - neither         → exit 2 with two AVAILABLE candidates ($CWD, $HOME).

Chosen-path handoff (WIKI_PATH):
  A WIKI_PATH argument skips discovery and answers for that path alone,
  mirroring lint.py's optional positional wiki_path: an existing directory
  prints its canonical path and exits 0, a missing one exits 1. The wiki
  predicate is not applied, so the caller can hand back the candidate the
  user picked from an exit-2 list instead of re-running discovery.

Usage:
  discover_wiki.sh [WIKI_PATH] [--check]

  Supported shapes: no arguments, --check, WIKI_PATH, WIKI_PATH --check,
  and -h / --help. Every other shape exits 3.

Options:
  --check     Exit 1 if the resolved path does not exist on disk.
  -h, --help  Show this help.

Exit codes:
  0  a single resolved path on stdout
  1  the resolved path or the given WIKI_PATH does not exist on disk
  2  ambiguous: candidate list on stdout, ask the user
  3  usage error: message on stderr, nothing on stdout
USAGE
}

usage_error() {
  # Exit 3, kept distinct from the exit-2 ambiguity signal: a caller that
  # reads exit 2 as "candidates on stdout" would otherwise take a usage
  # mistake for an empty candidate list. Nothing goes to stdout here.
  printf 'discover_wiki.sh: %s\n' "$1" >&2
  printf 'usage: discover_wiki.sh [WIKI_PATH] [--check]   (--help for detail)\n' >&2
  exit 3
}

# Supported argument shapes: no arguments, --check, WIKI_PATH,
# WIKI_PATH --check, and -h / --help on its own. An empty WIKI_PATH counts
# as no path, matching lint.py's falsy `if arg:` gate on its positional.
case $# in
  0)
    ;;
  1)
    case "$1" in
      -h|--help) print_help; exit 0 ;;
      --check)   CHECK=true ;;
      -*)        usage_error "unknown argument: $1" ;;
      *)         WIKI_ARG=$1 ;;
    esac
    ;;
  2)
    case "$2" in
      --check) ;;
      *) usage_error "unsupported argument shape: $1 $2" ;;
    esac
    case "$1" in
      -*) usage_error "unknown argument: $1" ;;
      *)  WIKI_ARG=$1; CHECK=true ;;
    esac
    ;;
  *)
    usage_error "too many arguments ($#); expected at most WIKI_PATH --check"
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

is_wiki() {
  # True when $1 is a usable wiki: it carries no .no_wiki opt-out, its
  # basename contains "wiki" (case-insensitive), and at least two of the
  # three markers SCHEMA.md / index.md / log.md exist directly inside it.
  # .no_wiki takes precedence over wiki-ness, so a retired wiki is dropped.
  local dir=$1
  [[ -f "$dir/.no_wiki" ]] && return 1
  local base_lc
  base_lc=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
  case "$base_lc" in
    *wiki*) ;;
    *) return 1 ;;
  esac
  local count=0 marker
  for marker in SCHEMA.md index.md log.md; do
    [[ -f "$dir/$marker" ]] && count=$((count + 1))
  done
  [[ $count -ge 2 ]]
}

# A given WIKI_PATH answers for itself: discovery is what the caller
# already ran to get this path, so re-running it here would only reproduce
# the same ambiguous list. Mirrors lint.py's positional wiki_path — the
# wiki predicate stays out, so an AVAILABLE: level the user chose resolves
# just as an EXISTING: wiki does.
if [[ -n "$WIKI_ARG" ]]; then
  # Expand a leading ~ the way lint.py's Path.expanduser() does, for a path
  # handed over as a literal string rather than through shell expansion. The
  # tilde lives in a variable so these stay patterns matching a literal ~
  # rather than quoted tildes shellcheck reads as failed expansions (SC2088).
  tilde='~'
  case "$WIKI_ARG" in
    "$tilde")   WIKI_ARG=$HOME ;;
    "$tilde"/*) WIKI_ARG="$HOME/${WIKI_ARG#"$tilde"/}" ;;
  esac
  if [[ -d "$WIKI_ARG" ]]; then
    printf '%s\n' "$(abs "$WIKI_ARG")"
    exit 0
  fi
  case "$WIKI_ARG" in
    /*) missing=$WIKI_ARG ;;
    *)  missing="$(pwd -P)/$WIKI_ARG" ;;
  esac
  echo "wiki path does not exist: $missing" >&2
  exit 1
fi

cwd=$(abs "$PWD")
home=$(abs "$HOME")

# Standing in a wiki resolves to it directly, before any walk-up or the
# under-$HOME / outside-$HOME split. .no_wiki at CWD suppresses this (it is
# folded into is_wiki), so a retired wiki you stand in is not resolved.
if is_wiki "$cwd"; then
  printf '%s\n' "$cwd"
  if $CHECK && [[ ! -d "$cwd" ]]; then
    exit 1
  fi
  exit 0
fi

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
# At each level the existing wiki is the first child directory that is_wiki
# recognises, in lexical order over the level's visible children: the `*/`
# glob passes over dot-directories, and lint.py's mirror of this loop skips
# them too, so a dot-named wiki resolves the same way in both. break-on-
# first means a second matching sibling at the same level is deliberately
# not surfaced.
candidates=()
for level in "${ladder[@]}"; do
  if [[ -f "$level/.no_wiki" ]]; then
    continue
  fi
  found=""
  for child in "$level"/*/; do
    [[ -d "$child" ]] || continue
    child=${child%/}
    if is_wiki "$child"; then
      found=$child
      break
    fi
  done
  if [[ -n "$found" ]]; then
    candidates+=("EXISTING:$found")
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
