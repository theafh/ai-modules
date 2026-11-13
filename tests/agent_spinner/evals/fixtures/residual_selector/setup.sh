#!/usr/bin/env bash
# residual_selector: three release changelogs are closed comparison candidates
# for one judgement, and the ask also wants what the winner's notes leave out.
# The ask combines rows, so no single listed shape covers it. The run names the
# smallest covering shape it chose and proceeds under it, and writes no file.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/inputs"

cat > "$proj/inputs/changelog-3.0.md" <<'F'
# 3.0

- Removed the legacy importer.
- Renamed `--jobs` to `--workers`.
F

cat > "$proj/inputs/changelog-3.1.md" <<'F'
# 3.1

- `workers` now defaults to the core count instead of 4.
- Dropped the `importer.legacy` config key entirely.
F

cat > "$proj/inputs/changelog-3.2.md" <<'F'
# 3.2

- `--workers 0` now means "auto" rather than erroring.
F

cat > "$proj/inputs/issues-open.md" <<'F'
- #41 importer removal leaves stale config keys behind on upgrade.
- #58 published docs still show `--jobs`.
F

cat > "$proj/inputs/issues-closed.md" <<'F'
- #12 `--workers` rejected 0, fixed in 3.2.
- #33 upgrade from 2.x skipped the config rewrite step.
F

cat > "$proj/inputs/api.diff" <<'F'
--- a/config.toml
+++ b/config.toml
-importer = "legacy"
-jobs = 4
+workers = 0
F

cat > "$proj/inputs/schema.diff" <<'F'
--- a/schema/config.json
+++ b/schema/config.json
-  "importer": {"enum": ["legacy", "streaming"]},
+  "workers": {"type": "integer", "minimum": 0}
F

cat > "$proj/inputs/support-digest.md" <<'F'
Most common upgrade question: "my config still has `jobs` and the tool now
refuses to start." Second most common: "what does `--workers 0` do?"
F

cat > "$proj/inputs/benchmark-notes.md" <<'F'
On 8-core hosts, the 3.1 default doubles throughput against the old fixed 4.
On 2-core hosts it is a wash.
F

cat > "$proj/inputs/deprecations.md" <<'F'
`importer.legacy`: removed in 3.1, no shim.
`--jobs`: accepted with a warning in 3.0, removed in 3.1.
F

seal "$target" "$proj"
echo "residual_selector sandbox staged at $proj"
