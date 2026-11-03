#!/usr/bin/env bash
# smoke_inline_body: an empty sandbox. The eval asks the worker to write the
# first non-blank line of the skill body it received inline, so a run that
# read the staged SKILL.md instead writes the frontmatter's opening line.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
printf 'smoke sandbox\n' > "$proj/README.txt"

seal "$target" "$proj"
echo "smoke_inline_body sandbox staged at $proj"
