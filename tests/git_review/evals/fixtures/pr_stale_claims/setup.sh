#!/usr/bin/env bash
# The pull request body states a version and a test count the branch does not
# carry, so each claim is stale against the tree.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src tests
printf '{\n  "name": "widget",\n  "version": "2.3.0"\n}\n' > package.json
printf 'def convert(rows):\n    return rows\n' > src/convert.py
printf 'def test_convert():\n    assert True\n' > tests/test_convert.py
git add -A
git commit --quiet -m "seed widget at 2.3.0 with one test"
git push --quiet origin main
make_remote_look_like_github "$repo" "$target/origin.git"

git checkout --quiet -b feature/export
printf '{\n  "name": "widget",\n  "version": "2.4.0"\n}\n' > package.json
printf 'def convert(rows):\n    return rows\n\n\ndef export(rows):\n    return list(rows)\n' > src/convert.py
printf 'def test_convert():\n    assert True\n\n\ndef test_export():\n    assert True\n' > tests/test_convert.py
git add -A
git commit --quiet -m "Add an export helper, bump to 2.4.0, and add its test"
git push --quiet -u origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"
cat > "$payloads/pr.json" <<JSON
{
  "number": 7,
  "title": "Export command",
  "body": "Ships widget 3.1.0 and adds 12 new tests covering the export path.",
  "headRefName": "feature/export",
  "baseRefName": "main",
  "headRefOid": "$head_oid",
  "state": "OPEN",
  "isDraft": false,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN",
  "reviewDecision": null,
  "additions": 8,
  "deletions": 2,
  "changedFiles": 3
}
JSON
install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads"
printf '%s\n' "$repo"
