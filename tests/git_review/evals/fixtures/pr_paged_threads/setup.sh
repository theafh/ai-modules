#!/usr/bin/env bash
# The pull request's inline review threads span two pages and include one
# resolved thread and one outdated thread, so a run that stops after the first
# page or filters those two away is visibly incomplete.

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
printf 'def convert(rows):\n    return rows\n\n\ndef export(rows, path):\n    open(path, "w").write(str(rows))\n' > src/convert.py
git add -A
git commit --quiet -m "src/convert.py -> add an export helper beside convert"
git push --quiet -u origin feature/export
head_oid="$(git rev-parse HEAD)"

payloads="$target/payloads"
default_pr_payloads "$payloads" "$head_oid"

cat > "$payloads/review_threads_page1.json" <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "pageInfo": {"hasNextPage": true, "endCursor": "CURSOR_PAGE_2"},
          "nodes": [
            {
              "id": "T_open_handle",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/convert.py",
              "line": 5,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "peer"}, "body": "The file handle is never closed.", "createdAt": "2026-08-30T10:01:00Z"}
                ]
              }
            }
          ]
        }
      }
    }
  }
}
JSON

cat > "$payloads/review_threads_page2.json" <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "pageInfo": {"hasNextPage": false, "endCursor": null},
          "nodes": [
            {
              "id": "T_resolved_naming",
              "isResolved": true,
              "isOutdated": false,
              "path": "src/convert.py",
              "line": 4,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "peer"}, "body": "Rename the helper to write_rows.", "createdAt": "2026-08-30T10:02:00Z"},
                  {"author": {"login": "author"}, "body": "Resolved: renamed.", "createdAt": "2026-08-30T10:20:00Z"}
                ]
              }
            },
            {
              "id": "T_outdated_import",
              "isResolved": false,
              "isOutdated": true,
              "path": "src/convert.py",
              "line": 1,
              "comments": {
                "pageInfo": {"hasNextPage": false, "endCursor": null},
                "nodes": [
                  {"author": {"login": "peer"}, "body": "This import moved in a later push.", "createdAt": "2026-08-30T10:03:00Z"}
                ]
              }
            }
          ]
        }
      }
    }
  }
}
JSON

install_gh_stub "$target" "$payloads" >/dev/null
write_gh_env "$target" "$payloads"
printf '%s\n' "$repo"
