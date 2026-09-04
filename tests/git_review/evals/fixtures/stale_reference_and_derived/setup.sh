#!/usr/bin/env bash
# The change renames a file a standing instruction still references, and edits
# the source of a derived artifact without regenerating that artifact.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src docs
printf 'def run(args):\n    """Entry point."""\n    return args\n' > src/runner.py
cat > src/commands.yaml <<'YML'
commands:
  - name: run
    summary: Run the pipeline over the given arguments.
YML
cat > docs/commands.md <<'MD'
<!-- Generated from src/commands.yaml by `make docs`. Do not edit by hand. -->

# Commands

## run

Run the pipeline over the given arguments.
MD
plant_standing_instructions "$repo" 'Start every session by reading `src/runner.py`; it holds the entry point and
the argument contract every command follows. Regenerate `docs/commands.md`
with `make docs` after editing `src/commands.yaml`.'
plant_makefile "$repo" "./tests/run_tests.sh"
git add -A
git commit --quiet -m "seed runner, command definitions, and generated docs"
git push --quiet origin main

git checkout --quiet -b rename-entry-point
git mv src/runner.py src/entrypoint.py
cat > src/commands.yaml <<'YML'
commands:
  - name: run
    summary: Run the pipeline over the given arguments.
  - name: verify
    summary: Check the pipeline configuration without running it.
YML
git add -A
git commit --quiet -m "Rename the runner module to entrypoint and add a verify command"
git push --quiet -u origin rename-entry-point
printf '%s\n' "$repo"
