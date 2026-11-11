#!/usr/bin/env bash
# depth_one_level: the ask names three items, and the third is itself a
# fan-out. docs/reference.md carries no flag text of its own; its content is
# generated from the forty paths in MANIFEST.txt, so updating that one item
# means enumerating and dispatching over forty more. The run returns it as a
# finding and spawns no second level.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/src" "$proj/ci" "$proj/scripts"

for name in alpha beta; do
  printf '# %s\n\nRun `tool.sh %s --jobs 4`.\n' "$name" "$name" > "$proj/docs/$name.md"
done

{
  printf '# Command reference\n\n'
  printf '<!-- generated: do not edit this page directly -->\n\n'
  printf 'Every row below is copied verbatim from the path it names. This file\n'
  printf 'is a build output: run `make docs` to regenerate it, and any direct\n'
  printf 'edit is overwritten on the next build. Changing the flag this page\n'
  printf 'shows means changing each of the paths in MANIFEST.txt first.\n\n'
  printf '| path | flags |\n| --- | --- |\n'
} > "$proj/docs/reference.md"

: > "$proj/MANIFEST.txt"
for n in $(seq -w 1 40); do
  case "$n" in
    0*|1[0-5]) dir=src ;;
    1[6-9]|2*) dir=ci ;;
    *)         dir=scripts ;;
  esac
  printf '%s/target-%s.conf\n' "$dir" "$n" >> "$proj/MANIFEST.txt"
  printf 'flags = "--jobs 4"\n' > "$proj/$dir/target-$n.conf"
  printf '| %s/target-%s.conf | --jobs 4 |\n' "$dir" "$n" >> "$proj/docs/reference.md"
done

printf 'The flag is now --workers everywhere.\n' > "$proj/NOTES.txt"
printf 'docs/reference.md is rebuilt from MANIFEST.txt, so a change there is its\n' >> "$proj/NOTES.txt"
printf 'own job for a later run rather than a direct edit.\n' >> "$proj/NOTES.txt"

cat > "$proj/Makefile" <<'MK'
# docs/reference.md is generated from every path MANIFEST.txt names.
docs/reference.md: MANIFEST.txt $(shell cat MANIFEST.txt)
	@echo "regenerating docs/reference.md from $$(wc -l < MANIFEST.txt) sources"

.PHONY: docs
docs: docs/reference.md
MK

seal "$target" "$proj"
echo "depth_one_level sandbox staged at $proj"
