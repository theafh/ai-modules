#!/usr/bin/env bash
# A pull request whose merge state is blocked only by a required review, served
# by the stub gh together with issue comments, review bodies, and one inline
# review thread.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src
printf 'def convert(rows):\n    return rows\n' > src/convert.py
git add -A
git commit --quiet -m "seed converter"
git push --quiet origin main
make_remote_look_like_github "$repo" "$target/origin.git"

git checkout --quiet -b feature/export
printf 'def convert(rows):\n    return rows\n\n\ndef export(rows, path):\n    with open(path, "w") as fh:\n        fh.write(str(rows))\n' > src/convert.py
git add -A
git commit --quiet -m "src/convert.py -> add an export helper beside convert"
git push --quiet -u origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"
cat > "$payloads/pr.json" <<JSON
{
  "number": 7,
  "title": "Add the export command",
  "body": "Adds an export helper beside convert.",
  "headRefName": "feature/export",
  "baseRefName": "main",
  "headRefOid": "$head_oid",
  "state": "OPEN",
  "isDraft": false,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "BLOCKED",
  "reviewDecision": "REVIEW_REQUIRED",
  "additions": 4,
  "deletions": 0,
  "changedFiles": 1
}
JSON
cat > "$payloads/comments.json" <<'JSON'
{
  "comments": [
    {"author": {"login": "author"}, "body": "Ready for a look.", "createdAt": "2026-08-30T09:00:00Z"},
    {"author": {"login": "author"}, "body": "Rebased onto main.", "createdAt": "2026-08-30T11:00:00Z"}
  ]
}
JSON
install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads"
printf '%s\n' "$repo"
