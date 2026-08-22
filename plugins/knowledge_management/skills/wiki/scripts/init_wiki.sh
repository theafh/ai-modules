#!/usr/bin/env bash
# init_wiki.sh — create a fresh wiki structure at a given path.
#
# Creates SCHEMA.md, index.md, log.md, and the standard directory tree
# (raw/{articles,papers,meetings,notes,assets}, entities, concepts,
# comparisons, queries, summaries, procedures). Templates are
# intentionally minimal — the agent customizes SCHEMA.md (domain, tag
# taxonomy) after asking the user.
#
# Refuses to create when:
#   - SCHEMA.md, index.md, or log.md already exists at the target (would
#     overwrite an established wiki)
#   - a `.no_wiki` opt-out marker is present at the target itself
#     (a wiki dir that has been deliberately retired)
#
# Pair with discover_wiki.sh:
#   path=$(scripts/discover_wiki.sh)
#   [[ -d "$path" ]] || scripts/init_wiki.sh "$path"
#
# Usage:
#   scripts/init_wiki.sh PATH

set -euo pipefail

case "${1:-}" in
  -h|--help|'')
    cat <<'USAGE'
init_wiki.sh — create a fresh wiki structure at a given path.

Usage:
  init_wiki.sh PATH

Creates SCHEMA.md, index.md, log.md, and the standard directory tree.
Refuses to overwrite an existing wiki and respects a `.no_wiki`
opt-out marker at the target path itself.

Pair with discover_wiki.sh:
  path=$(scripts/discover_wiki.sh)
  [[ -d "$path" ]] || scripts/init_wiki.sh "$path"
USAGE
    [[ -z "${1:-}" ]] && exit 2 || exit 0
    ;;
esac

WIKI="$1"

# Honor the opt-out marker on the target itself: a directory deliberately
# marked .no_wiki should not be re-initialized as a wiki.
if [[ -f "$WIKI/.no_wiki" ]]; then
  echo "refusing to init at $WIKI (.no_wiki marker present)" >&2
  exit 1
fi

# Don't clobber an established wiki.
for f in SCHEMA.md index.md log.md; do
  if [[ -e "$WIKI/$f" ]]; then
    echo "refusing to overwrite existing wiki at $WIKI ($f present)" >&2
    exit 1
  fi
done

mkdir -p \
  "$WIKI/raw/articles" \
  "$WIKI/raw/papers" \
  "$WIKI/raw/meetings" \
  "$WIKI/raw/notes" \
  "$WIKI/raw/assets" \
  "$WIKI/entities" \
  "$WIKI/concepts" \
  "$WIKI/comparisons" \
  "$WIKI/queries" \
  "$WIKI/summaries" \
  "$WIKI/procedures"

today="$(date +%Y-%m-%d)"
# The log seed heading carries a timestamp so every entry heading is unique
# by construction; index.md's `Last updated:` stays date-only. Local
# wall-clock time in the same locality as $today, on purpose.
now="$(date "+%Y-%m-%d %H:%M")"

# Templates are the single source of truth for the wiki shape, kept in
# ../references/ alongside this script. SCHEMA.md is copied verbatim;
# index.md substitutes {{TODAY}} for the date-only create date, and log.md
# substitutes {{NOW}} for the date+time its seed entry heading carries.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS="$SCRIPT_DIR/../references"

for f in template_schema.md template_index.md template_log.md; do
  if [[ ! -f "$REFS/$f" ]]; then
    echo "missing template: $REFS/$f" >&2
    exit 1
  fi
done

cp "$REFS/template_schema.md" "$WIKI/SCHEMA.md"
sed "s/{{TODAY}}/$today/g" "$REFS/template_index.md" > "$WIKI/index.md"
sed -e "s/{{NOW}}/$now/g" -e "s/{{TODAY}}/$today/g" \
  "$REFS/template_log.md" > "$WIKI/log.md"

echo "initialized wiki at $WIKI"
echo "next: customize SCHEMA.md (domain + tag taxonomy) with the user"
