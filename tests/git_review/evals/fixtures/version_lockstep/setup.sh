#!/usr/bin/env bash
# The change bumps a component version without updating the manifest files the
# repository's standing versioning rules name.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p components/reporter registry
cat > components/reporter/component.json <<'JSON'
{
  "name": "reporter",
  "version": "2.3.0"
}
JSON
cat > registry/components.json <<'JSON'
{
  "components": [
    {"name": "reporter", "version": "2.3.0"}
  ]
}
JSON
cat > registry/mirror.json <<'JSON'
{
  "components": [
    {"name": "reporter", "version": "2.3.0"}
  ]
}
JSON
plant_standing_instructions "$repo" 'When a component version rises in `components/<name>/component.json`, raise it
to the same value in `registry/components.json` and `registry/mirror.json` in
the same commit. The three files stay in lockstep.'
git add -A
git commit --quiet -m "seed the reporter component and both registry manifests"
git push --quiet origin main

git checkout --quiet -b bump-reporter
cat > components/reporter/component.json <<'JSON'
{
  "name": "reporter",
  "version": "2.4.0"
}
JSON
mkdir -p components/reporter/src
printf 'def summary(rows):\n    return len(rows)\n' > components/reporter/src/summary.py
git add -A
git commit --quiet -m "components/reporter -> add a summary helper and bump to 2.4.0"
git push --quiet -u origin bump-reporter
printf '%s\n' "$repo"
